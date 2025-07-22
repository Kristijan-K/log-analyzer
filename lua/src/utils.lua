local M = {}

---@param line string
---@return boolean
function M.is_timestamped_line(line)
	return line:match("^%d%d:%d%d:%d%d")
end

function M.ensure_teal_hl()
	vim.cmd("highlight default ApexLogTeal guifg=#20B2AA ctermfg=37")
	vim.cmd("highlight default ApexLogRed guifg=#FF0000 ctermfg=1")
end

function M.normalize_soql(soql)
	-- Lowercase, collapse whitespace for grouping
	return (soql or ""):lower():gsub("%s+", " ")
end

return M
