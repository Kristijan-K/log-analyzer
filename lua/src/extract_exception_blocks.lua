local M = {}

---@param lines string[]
---@return string[] exception_lines
function M.extract_exception_blocks(lines)
	local processed_lines = {}
	local seen_exceptions = {}

	local last_soql = nil
	for _, line in ipairs(lines) do
		if line:find("SOQL_EXECUTE_BEGIN") then
			-- Store whole soql string, if present
			local soql = line:match("[SELECT].*")
			if soql then
				last_soql = soql
			else
				last_soql = line
			end
		end
		local line_lower = line:lower()
		if line_lower:find("exception") and not line:find("SOQL_EXECUTE_BEGIN") then
			local processed_line = line
			local first_pipe = line:find("|")
			if first_pipe then
				local second_pipe = line:find("|", first_pipe + 1)
				if second_pipe then
					processed_line = line:sub(second_pipe + 1)
				end
			end
			processed_line = processed_line:gsub("^%s*(.-)%s*$", "%1")
			-- Compose exception info as table: { exception=processed_line, soql=last_soql or 'N/A' }
			local key = processed_line .. "||SOQL: " .. (last_soql or "N/A")
			if not seen_exceptions[key] then
				table.insert(processed_lines, { exception = processed_line, soql = last_soql or "N/A" })
				seen_exceptions[key] = true
			end
		end
	end

	-- Sort first by exception length
	table.sort(processed_lines, function(a, b)
		return #a.exception > #b.exception
	end)

	local filtered = {}
	for _, item in ipairs(processed_lines) do
		local is_substring = false
		for _, existing in ipairs(filtered) do
			if existing.exception:find(item.exception, 1, true) then
				is_substring = true
				break
			end
		end
		if not is_substring then
			table.insert(filtered, item)
		end
	end

	local indexed = {}
	if #filtered == 0 then
		table.insert(indexed, "No exceptions or errors found.")
	else
		for i, v in ipairs(filtered) do
			-- Remove newlines from v.exception and v.soql for format string substitution
			local one_line_exception = v.exception:gsub("\n", " ")
			local one_line_soql = v.soql:gsub("\n", " ")
			table.insert(indexed, string.format("%d. %s", i, one_line_exception))
			table.insert(indexed, string.format("   SOQL: %s", one_line_soql))
		end
	end

	return indexed
end
return M
