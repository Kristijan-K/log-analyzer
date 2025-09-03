local M = {}
---@param lines string[]
---@return string[] dml_lines, DMLHighlightSpan[] highlight_spans
function M.extract_dml_blocks(lines)
	local dml_blocks = {}
	local dml_pending = {}
	local dml_type_counts = {}

	for idx, line in ipairs(lines) do
		if line:find("|DML_BEGIN|", 1, true) then
			local ns1 = tonumber(line:match("%((%d+)%)"))
			local code_row = line:match("|DML_BEGIN|%[(%d+)%]")
			local op = line:match("Op:([^|]+)")
			local obj = line:match("Type:([^|]+)")
			local rows = tonumber(line:match("Rows:(%d+)") or "0")
			-- everything after [CODE_ROW]| for the right side (so [40]|Op:Insert|Type:Mariposa_Order__c|Rows:1 -> Op:Insert|Type:Mariposa_Order__c|Rows:1)
			local rest = line:match("|DML_BEGIN|%[%d+%]|(.+)")
			table.insert(dml_pending, {
				code_row = code_row or "",
				op = op or "",
				obj = obj or "",
				rows = rows,
				ns = ns1 or 0,
				log_idx = idx,
				matched = false,
				rest = rest or "",
			})
		elseif line:find("|DML_END|", 1, true) then
			local ns2 = tonumber(line:match("%((%d+)%)"))
			local code_row = line:match("|DML_END|%[(%d+)%]")
			-- Find the first unmatched BEGIN with same code_row
			for _, entry in ipairs(dml_pending) do
				if not entry.matched and entry.code_row == code_row then
					entry.ns2 = ns2 or 0
					entry.ms = entry.ns2 > entry.ns and (entry.ns2 - entry.ns) / 1e6 or 0
					entry.matched = true
					break
				end
			end
		end
	end

	-- Only keep matched ones
	for _, entry in ipairs(dml_pending) do
		if entry.matched then
			table.insert(dml_blocks, entry)
			local k = (entry.op or "") .. "(" .. (entry.obj or "") .. ")"
			dml_type_counts[k] = (dml_type_counts[k] or 0) + 1
		end
	end

	-- Sort by Rows, descending
	table.sort(dml_blocks, function(a, b)
		return a.rows > b.rows
	end)

	-- Type breakdown summary
	local typelines = {}
	for k, v in pairs(dml_type_counts) do
		table.insert(typelines, ("%s: %d"):format(k, v))
	end
	table.sort(typelines)

	-- Format
	local flat = {}
	if next(typelines) then
		table.insert(flat, "-- DML Statement Types: " .. table.concat(typelines, ", ") .. " --")
	else
		table.insert(flat, "No DML statements found.")
	end

	local highlight_spans = {}
	for idx, entry in ipairs(dml_blocks) do
		local indexstr = ("%d. "):format(idx)
		local code_str = entry.code_row ~= "" and ("[" .. entry.code_row .. "]") or ""
		local code_str2 = code_str ~= "" and (code_str .. " | ") or ""
		local index_start = #indexstr
		local index_end = index_start + #code_str
		local rowpart = "Rows:" .. tostring(entry.rows)
		local ms_part = ("%.2fms"):format(entry.ms or 0)
		local line = indexstr .. code_str2 .. entry.rest:gsub("Rows:%d+", rowpart) .. " | " .. ms_part
		table.insert(flat, line)
		if #code_str > 0 then
			table.insert(highlight_spans, { line = #flat - 1, from = index_start, to = index_end })
		end
	end
	return flat, highlight_spans
end
return M
