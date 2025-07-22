local M = {}

---@param lines string[]
---@return table, TreeNode[]
function M.extract_tree_blocks(lines)
	local open_close_map = {
		CODE_UNIT_STARTED = { close = "CODE_UNIT_FINISHED", extract_name = true },
		METHOD_ENTRY = { close = "METHOD_EXIT", extract_name = true },
		SYSTEM_METHOD_ENTRY = { close = "SYSTEM_METHOD_EXIT", extract_name = true },
		SOQL_EXECUTE_BEGIN = { close = "SOQL_EXECUTE_END", extract_name = false },
		DML_BEGIN = { close = "DML_END", extract_name = false },
		ENTERING_MANAGED_PKG = { close = nil, extract_name = false },
		USER_DEBUG = { close = nil, extract_name = false },
	}
	local closing_to_open = {}
	for k, v in pairs(open_close_map) do
		if v.close then
			closing_to_open[v.close] = k
		end
	end

	local function get_ns(line)
		return tonumber(line:match("%((%d+)%)")) or 0
	end
	local function get_code_row(line)
		return line:match("|%[(%d+)%]")
	end
	local function get_method_name(tag, line)
		if open_close_map[tag] and open_close_map[tag].extract_name then
			local parts = vim.split(line, "|")
			local fullName = vim.trim(parts[#parts] or tag)
			local paren = fullName:find("%(")
			if paren then
				return fullName:sub(1, paren - 1) .. "()"
			else
				return fullName
			end
		elseif tag == "ENTERING_MANAGED_PKG" then
			return "MANAGED CODE"
		elseif tag == "SOQL_EXECUTE_BEGIN" then
			local soql = line:match("[SELECT].*")
			if soql and soql_truncate then
				soql = soql:gsub("([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+", "%1 ... %2 ")
			end
			if soql and soql_truncate_where then
				soql = soql:gsub("%s+[wW][hH][eE][rR][eE]%s+.*", " ...")
			end
			return soql and ("SOQL: " .. soql) or "SOQL"
		elseif tag == "DML_BEGIN" then
			local op = line:match("Op:([^|]+)")
			local obj = line:match("Type:([^|]+)")
			return op and obj and ("DML: " .. op .. " " .. obj) or "DML"
		elseif tag == "USER_DEBUG" then
			return "USER_DEBUG"
		end
		return tag
	end

	-- Pass 1: Build flat list with parent/children references, expansion-ready
	local nodes = {}
	local stack = {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local ns = get_ns(line)
		local event_tag = nil
		for tag in pairs(open_close_map) do
			if line:find("|" .. tag .. "|", 1, true) then
				event_tag = tag
				break
			end
		end
		for tag in pairs(closing_to_open) do
			if line:find("|" .. tag .. "|", 1, true) then
				event_tag = tag
				break
			end
		end

		if open_close_map[event_tag] then
			local name = get_method_name(event_tag, line)
			local code_row = get_code_row(line)
			local node = {
				tag = event_tag,
				name = name,
				code_row = code_row,
				start_ns = ns,
				end_ns = nil,
				children = {},
				parent = stack[#stack],
				line_idx = i,
				expanded = true,
				soql_count = 0, -- Initialize SOQL count
				dml_count = 0, -- Initialize DML count
			}
			table.insert(nodes, node)
			if node.parent then
				table.insert(node.parent.children, node)
			end
			if event_tag == "SOQL_EXECUTE_BEGIN" then
				node.soql_count = node.soql_count + 1
			elseif event_tag == "DML_BEGIN" then
				node.dml_count = node.dml_count + 1
			end
			if open_close_map[event_tag].close then
				table.insert(stack, node)
			end
		elseif closing_to_open[event_tag] then
			local open_tag = closing_to_open[event_tag]
			for j2 = #stack, 1, -1 do
				local n = stack[j2]
				if n and n.tag == open_tag and not n.end_ns then
					n.end_ns = ns
					table.remove(stack, j2)
					break
				end
			end
		end
		i = i + 1
	end

	-- Set .end_ns for single/no-close nodes as next node, else self
	for k, node in ipairs(nodes) do
		if not node.end_ns then
			local next = nodes[k + 1]
			node.end_ns = next and next.start_ns or node.start_ns
		end
	end

	-- Aggregation pass: flatten all consecutive MANAGED CODE siblings under the same parent into a single node
	local function aggregate_managed_code(children)
		local aggregated = {}
		local idx = 1
		while idx <= #children do
			local node = children[idx]
			if node.tag == "ENTERING_MANAGED_PKG" then
				-- start grouping
				local group_start = idx
				local group_end = idx
				while group_end + 1 <= #children and children[group_end + 1].tag == "ENTERING_MANAGED_PKG" do
					group_end = group_end + 1
				end
				if group_end > group_start then
					local first = children[group_start]
					local last = children[group_end]
					table.insert(aggregated, {
						tag = "ENTERING_MANAGED_PKG",
						name = "MANAGED CODE (" .. (group_end - group_start + 1) .. " seq.)",
						code_row = nil,
						start_ns = first.start_ns,
						end_ns = last.end_ns,
						children = {},
						parent = first.parent,
						expanded = true,
					})
				else
					table.insert(aggregated, node)
				end
				idx = group_end + 1
			else
				-- For tree nodes, recurse into its children
				if node.children and #node.children > 0 then
					node.children = aggregate_managed_code(node.children)
				end
				table.insert(aggregated, node)
				idx = idx + 1
			end
		end
		return aggregated
	end

	-- Top-level root nodes
	local roots = {}
	for _, n in ipairs(nodes) do
		if not n.parent then
			table.insert(roots, n)
		end
	end
	roots = aggregate_managed_code(roots)
	-- and for all descendant nodes:
	local function aggregate_descendants(node)
		if node.children and #node.children > 0 then
			node.children = aggregate_managed_code(node.children)
			for _, child in ipairs(node.children) do
				aggregate_descendants(child)
			end
		end
	end
	for _, r in ipairs(roots) do
		aggregate_descendants(r)
	end

	-- New aggregation for identical, childless siblings
	local function aggregate_identical_siblings_recursive(children)
		if not children or #children == 0 then
			return children
		end

		-- First, recurse on children of children
		for _, child in ipairs(children) do
			if child.children and #child.children > 0 then
				child.children = aggregate_identical_siblings_recursive(child.children)
			end
		end

		local aggregated_children = {}
		local i = 1
		while i <= #children do
			local current_node = children[i]
			if #current_node.children == 0 then -- Only aggregate leaf nodes
				local group_end = i
				while
					group_end + 1 <= #children
					and children[group_end + 1].name == current_node.name
					and children[group_end + 1].code_row == current_node.code_row
					and #children[group_end + 1].children == 0
				do
					group_end = group_end + 1
				end

				if group_end > i then
					local total_ns = 0
					local total_soql = 0
					local total_dml = 0
					local total_own_soql = 0
					local total_own_dml = 0
					for j = i, group_end do
						total_ns = total_ns + ((children[j].end_ns or children[j].start_ns) - children[j].start_ns)
					end
					local new_node = {
						tag = current_node.tag,
						name = current_node.name .. " (x" .. (group_end - i + 1) .. ")",
						code_row = current_node.code_row,
						start_ns = current_node.start_ns,
						end_ns = current_node.start_ns + total_ns,
						children = {},
						parent = current_node.parent,
						expanded = false,
						line_idx = current_node.line_idx,
						soql_count = current_node.soql_count,
						dml_count = current_node.dml_count,
						own_soql_count = current_node.own_soql_count,
						own_dml_count = current_node.own_dml_count,
					}
					table.insert(aggregated_children, new_node)
					i = group_end + 1
				else
					table.insert(aggregated_children, current_node)
					i = i + 1
				end
			else
				table.insert(aggregated_children, current_node)
				i = i + 1
			end
		end
		return aggregated_children
	end
	roots = aggregate_identical_siblings_recursive(roots)

	-- Compute durations for all nodes, collect them for "10 Longest"
	local durations = {}
	local function collect_durations(node)
		node.duration = ((node.end_ns or node.start_ns) - node.start_ns) / 1e6
		table.insert(durations, { node = node, ms = node.duration })
		if node.children then
			for _, child in ipairs(node.children) do
				collect_durations(child)
			end
		end
	end

	local function aggregate_soql_dml(node)
		node.own_soql_count = 0
		node.own_dml_count = 0

		if node.children then
			for _, child in ipairs(node.children) do
				if child.tag == "SOQL_EXECUTE_BEGIN" then
					node.own_soql_count = (node.own_soql_count or 0) + 1
				elseif child.tag == "DML_BEGIN" then
					node.own_dml_count = (node.own_dml_count or 0) + 1
				end
				aggregate_soql_dml(child)
				node.soql_count = (node.soql_count or 0) + (child.soql_count or 0)
				node.dml_count = (node.dml_count or 0) + (child.dml_count or 0)
			end
		end
		node.has_soql_or_dml = (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0)
	end

	for _, r in ipairs(roots) do
		collect_durations(r)
		aggregate_soql_dml(r)
	end
	table.sort(durations, function(a, b)
		return a.ms > b.ms
	end)

	-- 10 Longest
	local longest = {}
	for idx = 1, math.min(10, #durations) do
		local node = durations[idx].node
		local cr = node.code_row and (" [" .. node.code_row .. "]") or ""
		table.insert(longest, string.format("%2d. %s%s | %.2fms", idx, node.name, cr, node.duration))
	end

	return longest, roots
end
return M
