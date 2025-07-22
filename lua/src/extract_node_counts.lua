local M = {}

---@param roots TreeNode[]
---@return string[]
function M.extract_node_counts(roots, soql_truncate_flag, soql_truncate_where_flag)
	local counts = {}
	local function traverse(node)
		if node.has_soql_or_dml then
			local name

			if node and node.name then
				name = node.name:gsub(" %(x%d+%)", "") -- remove (xN) from name
			else
				-- handle error
				-- e.g., local name = ''
			end
			if soql_truncate_flag then
				name = name:gsub("([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+", "%1 ... %2 ")
			end
			if soql_truncate_where_flag then
				name = name:gsub("%s+[wW][hH][eE][rR][eE]%s+.*", " ...")
			end
			local repetition_count = 1
			local rep_match = node.name:match("%(x(%d+)%)")
			if rep_match then
				repetition_count = tonumber(rep_match)
			end

			if not counts[name] then
				counts[name] = { total_count = 0, total_own_soql = 0, total_own_dml = 0 }
			end
			counts[name].total_count = counts[name].total_count + 1
			if counts[name].total_own_soql == 0 then
				counts[name].total_own_soql = (node.own_soql_count or 0)
			end
			if counts[name].total_own_dml == 0 then
				counts[name].total_own_dml = (node.own_dml_count or 0)
			end
		end
		if node.children then
			for _, child in ipairs(node.children) do
				traverse(child)
			end
		end
	end

	for _, root in ipairs(roots) do
		traverse(root)
	end

	local sorted_counts = {}
	for name, data in pairs(counts) do
		table.insert(sorted_counts, {
			name = name,
			total_count = data.total_count,
			total_own_soql = data.total_own_soql,
			total_own_dml = data.total_own_dml,
		})
	end

	table.sort(sorted_counts, function(a, b)
		return a.total_count > b.total_count
	end)

	local lines = {}
	local highlight_spans = {}
	for i, item in ipairs(sorted_counts) do
		local soql_dml_part = ""
		local soql_dml_part_start_col = 0
		local soql_dml_part_end_col = 0

		if item.total_own_soql > 0 or item.total_own_dml > 0 then
			soql_dml_part = string.format(" (Own SOQL:%d Own DML:%d)", item.total_own_soql, item.total_own_dml)
			soql_dml_part_start_col = #string.format("%d. %s: %d", i, item.name, item.total_count) + 1
			soql_dml_part_end_col = soql_dml_part_start_col + #soql_dml_part - 1
		end
		local line_str = string.format("%d. %s: %d%s", i, item.name, item.total_count, soql_dml_part)
		table.insert(lines, line_str)

		local current_line_idx = #lines - 1

		if soql_dml_part_start_col > 0 then
			table.insert(highlight_spans, {
				line = current_line_idx,
				from = soql_dml_part_start_col - 1,
				to = soql_dml_part_end_col,
				hl_group = "ApexLogTeal",
			})
		end
	end

	if #lines == 0 then
		return { "No nodes with SOQL or DML found." }, {}
	end

	return lines, highlight_spans
end
return M
