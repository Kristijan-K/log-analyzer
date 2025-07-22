local utils = require("src.utils")
local is_timestamped_line = utils.is_timestamped_line
local M = {}

---@param lines string[]
---@return string[] user_debug_lines, UserDebugHighlightSpan[] highlight_spans
function M.extract_user_debug_blocks(lines)
	local blocks = {}
	local in_debug = false
	local current = {}
	local highlight_spans = {}

	for idx, line in ipairs(lines) do
		if not in_debug and line:find("|USER_DEBUG|", 1, true) then
			in_debug = true
			current = { line }
		elseif in_debug and is_timestamped_line(line) then
			table.insert(blocks, vim.tbl_extend("force", {}, current))
			in_debug = false
			current = {}
		elseif in_debug then
			table.insert(current, line)
		end
	end
	if in_debug and #current > 0 then
		table.insert(blocks, current)
	end

	local flat = {}
	for idx, block in ipairs(blocks) do
		if #block > 0 then
			local first_line = block[1]
			local after_user_debug = first_line:match("|USER_DEBUG|(.*)")
			local line_number = after_user_debug and after_user_debug:match("%[(%d+)%]")
			local line_number_str = line_number and ("[" .. line_number .. "]") or ""
			local rest = after_user_debug and after_user_debug:gsub("^%s*%[%d+%]%|?DEBUG%|?", "") or ""
			local prefix = ("%d. "):format(idx)
			local line_text = prefix .. line_number_str .. rest
			table.insert(flat, line_text)
			if #line_number_str > 0 then
				table.insert(highlight_spans, { line = #flat - 1, from = #prefix, to = #prefix + #line_number_str })
			end
			for j = 2, #block do
				table.insert(flat, block[j])
			end
			table.insert(flat, "-----------------------------")
		end
	end
	if #flat > 0 then
		table.remove(flat, #flat)
	end
	return flat, highlight_spans
end
return M
