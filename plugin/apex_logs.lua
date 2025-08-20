vim.api.nvim_create_user_command('SFLogs', require('apex_logs').analyzeLogs, { desc = 'Analyze SF Logs' })
vim.api.nvim_create_user_command('SFDiff', require('apex_logs').diffLogs, { desc = 'Diff two SF Logs', nargs = '?' })
