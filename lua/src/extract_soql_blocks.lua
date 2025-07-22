local M = {}

---@param lines string[]
---@param sort_mode string
---@return string[] soql_lines, SOQLHighlightSpan[] highlight_spans
function M.extract_soql_blocks(lines, sort_mode)
	local agg = {}
	local idx_map = {}
	for idx, line in ipairs(lines) do
		if line:find("|SOQL_EXECUTE_BEGIN|", 1, true) then
			local ns1 = line:match("%((%d+)%)")
			local code_row = line:match("|SOQL_EXECUTE_BEGIN|%[(%d+)%]")
			local after = line:match("|SOQL_EXECUTE_BEGIN|%[%d+%]|[^|]*|([^|]+)")
			local soql = after and after:match("[SELECT].*$")
			idx_map[code_row or tostring(idx)] = {
				code_row = code_row or "",
				soql = soql or "",
				ns = tonumber(ns1),
				begin_idx = idx,
				rows = 0,
				ms = 0,
			}
		elseif line:find("|SOQL_EXECUTE_END|", 1, true) then
			local code_row = line:match("|SOQL_EXECUTE_END|%[(%d+)%]")
			local map = idx_map[code_row or ""]
			if map and map.ns then
				local ns2 = line:match("%((%d+)%)")
				local ms = ns2 and ((tonumber(ns2) - map.ns) / 1e6) or 0
				local rows = tonumber(line:match("Rows:(%d+)")) or 0
				-- Aggregate by normalized query
				local norm = normalize_soql(map.soql)
				if norm ~= "" then
					if not agg[norm] then
						agg[norm] = {
							soql = map.soql, -- raw, first version
							code_row = map.code_row,
							count = 0,
							total_rows = 0,
							max_ms = 0,
							sample_idx = map.begin_idx,
							row_counts = {},
						}
					end
					local a = agg[norm]
					a.count = a.count + 1
					a.total_rows = a.total_rows + rows
					table.insert(a.row_counts, rows)
					if ms > a.max_ms then
						a.max_ms = ms
					end
				end
			end
		end
	end

	-- Convert to list, sort according to mode
	local all = {}
	for _, v in pairs(agg) do
		table.insert(all, v)
	end

	if sort_mode == "execs" then
		table.sort(all, function(a, b)
			return a.count > b.count
		end)
	elseif sort_mode == "rows" then
		table.sort(all, function(a, b)
			return a.total_rows > b.total_rows
		end)
	elseif sort_mode == "ms" then
		table.sort(all, function(a, b)
			return a.max_ms > b.max_ms
		end)
	end

	-- Compute totals for summary
	local total_execs, total_rows = 0, 0
	for _, v in ipairs(all) do
		total_execs = total_execs + v.count
		total_rows = total_rows + v.total_rows
	end

	-- Prepare Top 5 block, always sorted by execution count
	local top5_sorted = {}
	for _, v in ipairs(all) do
		table.insert(top5_sorted, v)
	end
	table.sort(top5_sorted, function(a, b)
		return a.count > b.count
	end)

	local top5 = {}
	for i = 1, math.min(5, #top5_sorted) do
		local q = top5_sorted[i]
		local soql_str = q.soql:gsub("\n", " ")
		if soql_truncate then
			soql_str = soql_str:gsub("([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+", "%1 ... %2 ")
		end
		table.insert(
			top5,
			string.format("%d. %s | execs:%d | max %.2fms | rows:%d", i, soql_str, q.count, q.max_ms, q.total_rows)
		)
	end

	local sort_label = ({
		execs = "-- Sorted by: Executions --",
		rows = "-- Sorted by: Rows --",
		ms = "-- Sorted by: Time --",
	})[sort_mode or "execs"] or ""

	local flat, highlight_spans = {}, {}
	table.insert(flat, string.format("Total SOQL Executions: %d | Total Rows: %d", total_execs, total_rows))
	if #top5 > 0 then
		table.insert(flat, "---- Top 5 SOQL Statements ----")
		for _, l in ipairs(top5) do
			table.insert(flat, l)
		end
		table.insert(flat, "----------------------------------------")
	end
	table.insert(flat, sort_label)
	for idx, block in ipairs(all) do
		local prefix = ("%d. |"):format(idx)
		local code_row_str = block.code_row and ("[" .. block.code_row .. "]| ") or ""
		local index_start = #prefix
		local index_end = index_start + #code_row_str
		local soql_str = block.soql and block.soql or ""
		if soql_truncate then
			soql_str = soql_str:gsub("([sS][eE][lL][eE][cC][tT]).-%s+([fF][rR][oO][mM])%s+", "%1 ... %2 ")
		end
		local exec_str = "execs:" .. block.count
		local ms_str = ("max %.2fms"):format(block.max_ms)
		local rows_str = "rows:" .. table.concat(block.row_counts, "|")
		local line = prefix .. code_row_str .. soql_str .. " | " .. exec_str .. " | " .. ms_str .. " | " .. rows_str
		table.insert(flat, line)
		if #code_row_str > 0 then
			table.insert(highlight_spans, { line = #flat - 1, from = index_start, to = index_end - 1 })
		end
	end
	if #all == 0 then
		flat = { "No SOQL statements found." }
		highlight_spans = {}
	end
	return flat, highlight_spans
end
return M
