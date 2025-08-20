---@diagnostic disable: unused-local
require("src.model") -- for annotations (ensure 'src' is on your package.path)
---@diagnostic enable: unused-local

local utils = require("src.utils")
local dml_logic = require("src.extract_dml_blocks")
local node_logic = require("src.extract_node_counts")
local soql_logic = require("src.extract_soql_blocks")
local tree_block_logic = require("src.extract_tree_blocks")
local user_debug_logic = require("src.extract_user_debug_blocks")
local exception_logic = require("src.extract_exception_blocks")

local M = {}
local is_timestamped_line = utils.is_timestamped_line
local ensure_teal_hl = utils.ensure_teal_hl

local extract_dml_blocks = dml_logic.extract_dml_blocks
local extract_exception_blocks = exception_logic.extract_exception_blocks
local extract_node_counts = node_logic.extract_node_counts
local extract_soql_blocks = soql_logic.extract_soql_blocks
local extract_tree_blocks = tree_block_logic.extract_tree_blocks
local extract_user_debug_blocks = user_debug_logic.extract_user_debug_blocks

local api = vim.api

function M.analyzeLogs()
	ensure_teal_hl()
	local orig_lines = api.nvim_buf_get_lines(0, 0, -1, false)
	local ns = api.nvim_create_namespace("apex_log_teal")

	local tab_bufs = {}
	local sort_modes = { "execs", "rows", "ms" }
	local sort_mode_idx = 1
	local soql_sort_mode = sort_modes[sort_mode_idx]
	local user_debug_lines, userdebug_spans = extract_user_debug_blocks(orig_lines)
	local soql_lines, soql_spans = extract_soql_blocks(orig_lines, soql_sort_mode)

	local dml_lines, dml_spans = extract_dml_blocks(orig_lines)
	local exceptions = extract_exception_blocks(orig_lines)
	local show_soql_in_exceptions = false

	-- Tree state
	local tree_longest, tree_roots
	local tree_lines, tree_line_map
	local hide_empty_nodes = false

	local function render_exceptions()
		local indexed = {}
		if #exceptions == 0 then
			table.insert(indexed, "No exceptions or errors found.")
		else
			for i, v in ipairs(exceptions) do
				local one_line_exception = v.exception:gsub("\n", " ")
				table.insert(indexed, string.format("%d. %s", i, one_line_exception))
				if show_soql_in_exceptions then
					local one_line_soql = v.soql:gsub("\n", " ")
					table.insert(indexed, string.format("   SOQL: %s", one_line_soql))
				end
			end
		end
		return indexed
	end

	local function update_exception_view()
		local exception_lines = render_exceptions()
		api.nvim_buf_set_lines(tab_bufs[5], 0, -1, false, exception_lines)
	end

	local function filter_tree_nodes(nodes)
		local filtered = {}
		for _, node in ipairs(nodes) do
			local has_soql_or_dml = (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0)
			if hide_empty_nodes and not has_soql_or_dml then
			-- Skip this node if filtering and it has no SOQL/DML
			else
				-- Recursively filter children
				node.children = filter_tree_nodes(node.children)
				table.insert(filtered, node)
			end
		end
		return filtered
	end

	local function render_tree()
		local out_lines, out_map, out_highlights = {}, {}, {}
		local current_tree_roots = tree_roots
		if hide_empty_nodes then
			current_tree_roots = filter_tree_nodes(vim.deepcopy(tree_roots)) -- Deep copy to avoid modifying original tree_roots
		end

		local function render(node, depth)
			if hide_empty_nodes and not node.has_soql_or_dml then
				return
			end
			table.insert(out_map, node)
			local cr = node.code_row and (" [" .. node.code_row .. "]") or ""
			local indent = string.rep(" ", depth)
			local mark = (#node.children > 0) and (node.expanded and "▼ " or "▶ ") or "  "
			local soql_dml_info = ""
			if (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0) then
				soql_dml_info = string.format(" (SOQL:%d DML:%d)", node.soql_count or 0, node.dml_count or 0)
			end
			local own_soql_dml_info = ""
			if (node.own_soql_count and node.own_soql_count > 0) or (node.own_dml_count and node.own_dml_count > 0) then
				own_soql_dml_info =
					string.format(" (SOQL:%d DML:%d)", node.own_soql_count or 0, node.own_dml_count or 0)
			end

			local line = indent
				.. mark
				.. node.name
				.. cr
				.. soql_dml_info
				.. own_soql_dml_info
				.. string.format(" | %.2fms", node.duration)

			-- Store the highlight information for later application
			if (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0) then
				local start_col = #indent + #mark + #node.name + #cr + 1 -- +1 for the space before (SOQL:...
				local end_col = start_col + #soql_dml_info - 1
				table.insert(
					out_highlights,
					{ line_idx = #out_lines, start_col = start_col, end_col = end_col, hl_group = "ApexLogRed" }
				)
			end
			if (node.own_soql_count and node.own_soql_count > 0) or (node.own_dml_count and node.own_dml_count > 0) then
			local start_col = #indent + #mark + #node.name + #cr + #soql_dml_info + 1
			local end_col = start_col + #own_soql_dml_info - 1
			table.insert(
					out_highlights,
					{ line_idx = #out_lines, start_col = start_col, end_col = end_col, hl_group = "ApexLogTeal" }
				)
			end
			table.insert(out_lines, line)
			if node.expanded and node.children then
				for _, child in ipairs(node.children) do
					render(child, depth + 1)
				end
			end
		end

		if #tree_longest > 0 then
			for _, l in ipairs(tree_longest) do
				table.insert(out_lines, l)
				table.insert(out_map, { is_dummy = true })
			end
			table.insert(out_lines, "---- 10 Longest Operations ----")
			table.insert(out_map, { is_dummy = true })
		end
		for _, n in ipairs(tree_roots) do
			render(n, 0)
		end
		if #out_lines == 0 then
			table.insert(out_lines, "No method stack information found.")
			table.insert(out_map, {})
		end
		return out_lines, out_map, out_highlights
	end

	local function update_tree_view()
		local new_lines, new_map, new_highlights = render_tree()
		tree_lines = new_lines
		tree_line_map = new_map
		api.nvim_buf_set_lines(tab_bufs[2], 0, -1, false, tree_lines)
		-- Apply highlights after setting lines
		api.nvim_buf_clear_namespace(tab_bufs[2], ns, 0, -1)
		for _, hl in ipairs(new_highlights) do
			api.nvim_buf_add_highlight(tab_bufs[2], ns, hl.hl_group, hl.line_idx, hl.start_col, hl.end_col)
		end
	end

	-- Initial tree creation
	tree_longest, tree_roots = extract_tree_blocks(orig_lines)
	local node_count_lines, node_count_spans

	local function refresh_node_counts_buf()
		node_count_lines, node_count_spans = extract_node_counts(tree_roots)
		api.nvim_buf_set_lines(tab_bufs[6], 0, -1, false, node_count_lines)
		if current_tab == 6 then
			add_highlights(6)
		end
	end

		local tab_titles = { "User Debug", "Method Tree", "SOQL", "DML", "Exceptions", "Node Counts" }

		for i, title in ipairs(tab_titles) do
			local buf = api.nvim_create_buf(false, true)
			if i == 1 then
				api.nvim_buf_set_lines(buf, 0, -1, false, user_debug_lines)
			elseif i == 2 then
		-- initial tree view is now handled by switch_tab
			elseif i == 3 then
				api.nvim_buf_set_lines(buf, 0, -1, false, soql_lines)
			elseif i == 4 then
				api.nvim_buf_set_lines(buf, 0, -1, false, dml_lines)
			elseif i == 5 then
		-- Handled by update_exception_view()
			elseif i == 6 then
		-- Handled by refresh_node_counts_buf()
			else
				api.nvim_buf_set_lines(buf, 0, -1, false, { "This is the [" .. title .. "] tab." })
			end
			tab_bufs[i] = buf
		end

		-- Initial call for Node Counts tab
		refresh_node_counts_buf()
		update_exception_view()

		api.nvim_buf_set_keymap(tab_bufs[2], "n", "z", "", {
			noremap = true,
			nowait = true,
			callback = function()
					local win = api.nvim_get_current_win()
					local cur_line = api.nvim_win_get_cursor(win)[1]
					local node = tree_line_map[cur_line]
					if not node or node.is_dummy or not node.children or #node.children == 0 then
						return
				end
				node.expanded = not node.expanded
				update_tree_view()
				-- After re-rendering, the cursor might be off. We need to find the new line of the node.
				for i, n in ipairs(tree_line_map) do
					if n == node then
						api.nvim_win_set_cursor(win, { i, 0 })
						break
					end
				end
			end,
		})

		api.nvim_buf_set_keymap(tab_bufs[2], "n", "Z", "", {
			noremap = true,
			nowait = true,
			callback = function()
					local any_collapsed = false
					local function find_any_collapsed(nodes)
						for _, node in ipairs(nodes) do
							if any_collapsed then
								return
							end
							if #node.children > 0 and not node.expanded then
								any_collapsed = true
								return
							end
							if node.children and #node.children > 0 then
								find_any_collapsed(node.children)
							end
						end
				end
				find_any_collapsed(tree_roots)

				local new_state = any_collapsed
				local function set_all(nodes, state)
					for _, node in ipairs(nodes) do
						if #node.children > 0 then
							node.expanded = state
						end
						if node.children and #node.children > 0 then
							set_all(node.children, state)
						end
					end
				end
				set_all(tree_roots, new_state)
				update_tree_view()
			end,
		})

	-- Floating window setup
	local width = math.floor(vim.o.columns * 0.95)
	local height = math.floor(vim.o.lines * 0.90)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)
	local win = api.nvim_open_win(tab_bufs[1], true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		row = row,
		col = col,
		width = width,
		height = height,
	})
	vim.wo[win].winfixwidth = true
	vim.wo[win].winfixheight = true

	local function get_tabline(active_idx)
		local parts = {}
		for i, title in ipairs(tab_titles) do
			if i == active_idx then
				table.insert(parts, "%#TabLineSel#" .. title .. "%*")
			else
				table.insert(parts, "%#TabLine#" .. title .. "%*")
			end
		end
		return table.concat(parts, " | ")
	end

	local ns = api.nvim_create_namespace("apex_log_teal")
	local current_tab = 1
	local function clear_highlights()
		for _, buf in ipairs(tab_bufs) do
			api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		end
	end

	local function add_highlights(tab_idx)
		clear_highlights()
		local spans = (tab_idx == 1 and userdebug_spans)
			or (tab_idx == 3 and soql_spans)
			or (tab_idx == 4 and dml_spans)
			or (tab_idx == 6 and node_count_spans)
			or {}
		local buf = tab_bufs[tab_idx]
		for _, span in ipairs(spans or {}) do
			api.nvim_buf_add_highlight(buf, ns, "ApexLogTeal", span.line, span.from, span.to)
		end
	end
	local function refresh_soql_buf()
		local soql_lines2, soql_spans2 = extract_soql_blocks(orig_lines, soql_sort_mode)
		api.nvim_buf_set_lines(tab_bufs[3], 0, -1, false, soql_lines2)
		soql_spans = soql_spans2
		if current_tab == 3 then
			add_highlights(3)
		end
	end

	local function refresh_tree_buf()
		tree_longest, tree_roots = extract_tree_blocks(orig_lines)
		update_tree_view()
	end

	local function switch_tab(idx)
		if idx < 1 then
			idx = #tab_bufs
		end
		if idx > #tab_bufs then
			idx = 1
		end
		api.nvim_win_set_buf(win, tab_bufs[idx])
		vim.wo[win].winbar = get_tabline(idx)
		current_tab = idx
		add_highlights(current_tab)
		if idx == 2 then
			update_tree_view()
			vim.wo[win].wrap = false
		else
			vim.wo[win].wrap = true
		end
		if idx == 6 then
			refresh_node_counts_buf()
		end
	end

	switch_tab(1)
	add_highlights(1)

	for i, buf in ipairs(tab_bufs) do
		api.nvim_buf_set_keymap(buf, "n", "<Tab>", "", {
			noremap = true,
			nowait = true,
			callback = function()
				switch_tab(current_tab + 1)
			end,
		})
		api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "", {
			noremap = true,
			nowait = true,
			callback = function()
				switch_tab(current_tab - 1)
			end,
		})
		api.nvim_buf_set_keymap(buf, "n", "q", "", {
			noremap = true,
			nowait = true,
			callback = function()
				if api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, true)
				end
				for _, b in ipairs(tab_bufs) do
					pcall(api.nvim_buf_delete, b, { force = true })
				end
			end,
		})
		if i == 3 then
			-- SOQL tab: toggle sort mode with 'r'
			api.nvim_buf_set_keymap(buf, "n", "r", "", {
				noremap = true,
				nowait = true,
				callback = function()
					sort_mode_idx = (sort_mode_idx % #sort_modes) + 1
					soql_sort_mode = sort_modes[sort_mode_idx]
					refresh_soql_buf()
				end,
			})
			api.nvim_buf_set_keymap(buf, "n", "t", "", {
				noremap = true,
				nowait = true,
				callback = function()
					utils.set_soql_truncate(not utils.get_soql_truncate())
					refresh_soql_buf()
					refresh_tree_buf()
					refresh_node_counts_buf()
				end,
			})
		elseif i == 2 or i == 6 then
			-- Method Tree tab and Node Counts tab: toggle SOQL truncation with 't'
			api.nvim_buf_set_keymap(buf, "n", "t", "", {
				noremap = true,
				nowait = true,
				callback = function()
					utils.set_soql_truncate(not utils.get_soql_truncate())
					refresh_tree_buf()
					refresh_soql_buf()
					refresh_node_counts_buf()
				end,
			})
			api.nvim_buf_set_keymap(buf, "n", "T", "", {
				noremap = true,
				nowait = true,
				callback = function()
					utils.set_soql_truncate_where(not utils.get_soql_truncate_where())
					refresh_tree_buf()
					refresh_node_counts_buf()
					refresh_node_counts_buf()
				end,
			})
			api.nvim_buf_set_keymap(buf, "n", "s", "", {
				noremap = true,
				nowait = true,
				callback = function()
					hide_empty_nodes = not hide_empty_nodes
					refresh_tree_buf()
				end,
			})
		elseif i == 5 then
			-- Exceptions tab: toggle SOQL visibility with 's'
			api.nvim_buf_set_keymap(buf, "n", "s", "", {
				noremap = true,
				nowait = true,
				callback = function()
					show_soql_in_exceptions = not show_soql_in_exceptions
					update_exception_view()
				end,
			})
		end
	end
end

local function generate_tree_for_diff(lines)
	local tree_longest, tree_roots = extract_tree_blocks(lines)
	local out_lines = {}

	local function render(node, depth)
		local indent = string.rep(" ", depth)
		local mark = (#node.children > 0) and "▼ " or "  "
		local cr = node.code_row and (" [" .. node.code_row .. "]") or ""
		local soql_dml_info = ""
		if (node.soql_count and node.soql_count > 0) or (node.dml_count and node.dml_count > 0) then
			soql_dml_info = string.format(" (SOQL:%d DML:%d)", node.soql_count or 0, node.dml_count or 0)
		end
		local own_soql_dml_info = ""
		if (node.own_soql_count and node.own_soql_count > 0) or (node.own_dml_count and node.own_dml_count > 0) then
			own_soql_dml_info =
				string.format(" (SOQL:%d DML:%d)", node.own_soql_count or 0, node.own_dml_count or 0)
		end

		local line = indent
			.. mark
			.. node.name
			.. cr
			.. soql_dml_info
			.. own_soql_dml_info
			.. string.format(" | %.2fms", node.duration)

		table.insert(out_lines, line)
		if node.children then
			for _, child in ipairs(node.children) do
				render(child, depth + 1)
			end
		end
	end

	if #tree_longest > 0 then
		for _, l in ipairs(tree_longest) do
			table.insert(out_lines, l)
		end
		table.insert(out_lines, "---- 10 Longest Operations ----")
	end
	for _, n in ipairs(tree_roots) do
		render(n, 0)
	end

	if #out_lines == 0 then
		table.insert(out_lines, "No method stack information found.")
	end

	return out_lines
end

function M.diffLogs(args)
	local file1
	if #args.fargs == 1 then
		file1 = args.fargs[1]
	elseif #args.fargs == 0 then
		file1 = vim.api.nvim_buf_get_name(0)
	else
		vim.notify("SFDiff takes 0 or 1 argument.", vim.log.levels.ERROR)
		return
	end

	local has_telescope, telescope = pcall(require, "telescope")
	if not has_telescope then
		vim.notify("telescope.nvim is required for this feature.", vim.log.levels.ERROR)
		return
	end

	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	vim.notify("Select the second file to diff against.")
	require("telescope.builtin").find_files({
		prompt_title = "Diff against...",
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				if not selection then
					return
				end
				local file2 = selection.path

				-- The diff logic starts here
				local f1_content_result = io.open(file1, "r")
				if not f1_content_result then
					vim.notify("Could not read file: " .. file1, vim.log.levels.ERROR)
					return
				end
				local f1_content = f1_content_result:read("*a")
				f1_content_result:close()
				local f1_lines = vim.split(f1_content, "\n")

				local f2_content_result = io.open(file2, "r")
				if not f2_content_result then
					vim.notify("Could not read file: " .. file2, vim.log.levels.ERROR)
					return
				end
				local f2_content = f2_content_result:read("*a")
				f2_content_result:close()
				local f2_lines = vim.split(f2_content, "\n")

				local tree1_lines = generate_tree_for_diff(f1_lines)
				local tree2_lines = generate_tree_for_diff(f2_lines)

				local tmp1 = vim.fn.tempname()
				local tmp2 = vim.fn.tempname()

				vim.fn.writefile(tree1_lines, tmp1)
				vim.fn.writefile(tree2_lines, tmp2)

				vim.cmd("edit " .. tmp1)
				vim.cmd("vert diffsplit " .. tmp2)

				local win2_id = vim.api.nvim_get_current_win()
				vim.cmd("wincmd p")
				local win1_id = vim.api.nvim_get_current_win()
				vim.cmd("wincmd p")

				local bufnr1 = vim.fn.bufnr(tmp1)
				local bufnr2 = vim.fn.bufnr(tmp2)

				local callback = function()
					if vim.api.nvim_win_is_valid(win1_id) then
						vim.api.nvim_win_close(win1_id, true)
					end
					if vim.api.nvim_win_is_valid(win2_id) then
						vim.api.nvim_win_close(win2_id, true)
					end
				end

				vim.api.nvim_buf_set_keymap(bufnr1, "n", "q", "", { noremap = true, silent = true, callback = callback })
				vim.api.nvim_buf_set_keymap(bufnr2, "n", "q", "", { noremap = true, silent = true, callback = callback })

				local cleanup_group = vim.api.nvim_create_augroup("CleanupDiffs", { clear = true })
				vim.api.nvim_create_autocmd("BufWipeout", {
					pattern = { tmp1, tmp2 },
					group = cleanup_group,
					callback = function(event)
						vim.fn.delete(event.file)
					end,
				})
			end)
			return true
		end,
	})
end

return M