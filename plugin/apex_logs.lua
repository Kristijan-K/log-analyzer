vim.api.nvim_create_user_command('SFLogs', require('apex_logs').analyzeLogs, { desc = 'Analyze SF Logs' })
