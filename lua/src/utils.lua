local M = {}

local soql_truncate = false
local soql_truncate_where = false

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

function M.set_soql_truncate(value)
	soql_truncate = value
end

function M.get_soql_truncate()
	return soql_truncate
end

function M.set_soql_truncate_where(value)
	soql_truncate_where = value
end

function M.get_soql_truncate_where()
	return soql_truncate_where
end

return M