local actions = require("codegit.actions")
local config = require("codegit.config")
local git = require("codegit.git")
local render = require("codegit.render")
local state = require("codegit.state")

local M = {}

---@return table layout
local function compute_layout()
  local opts = config.options
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines - vim.o.cmdheight - 1

  local total_w = math.max(76, math.floor(editor_w * opts.width_ratio))
  local total_h = math.max(20, math.floor(editor_h * opts.height_ratio))
  local start_col = math.max(0, math.floor((editor_w - total_w) / 2))
  local start_row = math.max(0, math.floor((editor_h - total_h) / 2))

  local left_outer_w = math.floor(total_w * opts.sidebar_ratio)
  left_outer_w = math.max(opts.sidebar_min_width, math.min(opts.sidebar_max_width, left_outer_w))
  if total_w - left_outer_w < 36 then
    left_outer_w = math.max(24, math.floor(total_w * 0.35))
  end

  local gap = 1
  local right_outer_w = total_w - left_outer_w - gap
  local diff_l_outer_w = math.floor(right_outer_w / 2)
  local diff_r_outer_w = right_outer_w - diff_l_outer_w

  local commit_outer_h = opts.commit_height + 2
  local rem_h = math.max(10, total_h - commit_outer_h)
  local changes_outer_h = math.max(5, math.floor(rem_h * opts.changes_ratio))
  local graph_outer_h = math.max(5, rem_h - changes_outer_h)

  local right_col = start_col + left_outer_w + gap

  return {
    commit = {
      row = start_row,
      col = start_col,
      width = math.max(10, left_outer_w - 2),
      height = math.max(1, commit_outer_h - 2),
    },
    changes = {
      row = start_row + commit_outer_h,
      col = start_col,
      width = math.max(10, left_outer_w - 2),
      height = math.max(3, changes_outer_h - 2),
    },
    graph = {
      row = start_row + commit_outer_h + changes_outer_h,
      col = start_col,
      width = math.max(10, left_outer_w - 2),
      height = math.max(3, graph_outer_h - 2),
    },
    diff_left = {
      row = start_row,
      col = right_col,
      width = math.max(10, diff_l_outer_w - 2),
      height = math.max(5, total_h - 2),
    },
    diff_right = {
      row = start_row,
      col = right_col + diff_l_outer_w,
      width = math.max(10, diff_r_outer_w - 2),
      height = math.max(5, total_h - 2),
    },
  }
end

---@param name string
---@param modifiable boolean
---@return number buf
local function create_scratch_buf(name, modifiable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = modifiable
  pcall(vim.api.nvim_buf_set_name, buf, "codegit://" .. name)
  return buf
end

local panel_order = { "commit", "changes", "graph", "diff_left", "diff_right" }

---@param dir number 1 for next, -1 for prev
local function cycle_panel(dir)
  local cur = vim.api.nvim_get_current_win()
  local idx = 1
  for i, key in ipairs(panel_order) do
    if state.wins[key] == cur then
      idx = i
      break
    end
  end
  local next_idx = ((idx - 1 + dir) % #panel_order) + 1
  local target = state.wins[panel_order[next_idx]]
  if target and vim.api.nvim_win_is_valid(target) then
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(target)
  end
end

---@param key string
local function focus_panel(key)
  local target = state.wins[key]
  if target and vim.api.nvim_win_is_valid(target) then
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(target)
  end
end

function M.close()
  if not state.is_open then
    return
  end
  state.is_open = false

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end

  -- Turn off diff mode cleanly before closing diff windows
  for _, key in ipairs({ "diff_left", "diff_right" }) do
    local w = state.wins[key]
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(function()
        vim.wo[w].diff = false
        vim.wo[w].scrollbind = false
        vim.wo[w].cursorbind = false
      end)
    end
  end

  for _, key in ipairs(panel_order) do
    local w = state.wins[key]
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end

  if state.prev_scrollopt ~= nil then
    pcall(function()
      vim.o.scrollopt = state.prev_scrollopt
    end)
  end

  local prev = state.prev_win
  state.reset()

  if prev and vim.api.nvim_win_is_valid(prev) then
    pcall(vim.api.nvim_set_current_win, prev)
  end
end

local function setup_keymaps()
  local km = config.options.keymaps

  local function map(buf, mode, lhs, rhs)
    if not lhs or lhs == "" then
      return
    end
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true })
  end

  -- Global bindings across all 5 buffers (Normal mode)
  for _, key in ipairs(panel_order) do
    local buf = state.bufs[key]
    map(buf, "n", km.close, M.close)
    if key ~= "commit" then
      map(buf, "n", "<Esc>", M.close)
    end
    map(buf, "n", km.refresh, actions.refresh)
    map(buf, "n", km.help, actions.show_help)
    map(buf, "n", km.next_panel, function()
      cycle_panel(1)
    end)
    map(buf, "n", km.prev_panel, function()
      cycle_panel(-1)
    end)
    for num, target_key in ipairs(panel_order) do
      map(buf, "n", tostring(num), function()
        focus_panel(target_key)
      end)
    end
    if key ~= "commit" then
      map(buf, "n", km.commit_focus, actions.focus_commit)
    end
  end

  -- Git remote/branch/stash shortcuts on sidebar panels (so Vim motions b/f/z work in diff panes)
  for _, key in ipairs({ "changes", "graph" }) do
    local buf = state.bufs[key]
    map(buf, "n", km.pull, actions.pull)
    map(buf, "n", km.push, actions.push)
    map(buf, "n", km.fetch, actions.fetch)
    map(buf, "n", km.branch, actions.branch_menu)
    map(buf, "n", km.stash, actions.stash_menu)
  end

  -- Directional focus navigation
  map(state.bufs.commit, "n", "<C-j>", function() focus_panel("changes") end)
  map(state.bufs.commit, "n", "<C-l>", function() focus_panel("diff_left") end)

  map(state.bufs.changes, "n", "<C-k>", function() focus_panel("commit") end)
  map(state.bufs.changes, "n", "<C-j>", function() focus_panel("graph") end)
  map(state.bufs.changes, "n", "<C-l>", function() focus_panel("diff_left") end)

  map(state.bufs.graph, "n", "<C-k>", function() focus_panel("changes") end)
  map(state.bufs.graph, "n", "<C-l>", function() focus_panel("diff_left") end)

  map(state.bufs.diff_left, "n", "<C-h>", function() focus_panel("changes") end)
  map(state.bufs.diff_left, "n", "<C-l>", function() focus_panel("diff_right") end)

  map(state.bufs.diff_right, "n", "<C-h>", function() focus_panel("diff_left") end)

  -- Commit box bindings
  map(state.bufs.commit, "n", km.commit_submit_normal, actions.submit_commit)
  map(state.bufs.changes, "n", km.commit_submit_normal, actions.submit_commit)
  map(state.bufs.graph, "n", km.commit_submit_normal, actions.submit_commit)
  for _, mode in ipairs({ "n", "i" }) do
    map(state.bufs.commit, mode, km.commit_submit, actions.submit_commit)
    map(state.bufs.commit, mode, km.commit_submit_alt, actions.submit_commit)
  end

  -- Changes panel bindings
  local cbuf = state.bufs.changes
  map(cbuf, "n", "<Tab>", actions.preview_current)
  map(cbuf, "n", km.toggle_stage, actions.toggle_stage)
  map(cbuf, "n", km.toggle_stage_alt, actions.toggle_stage)
  map(cbuf, "n", km.stage_all, actions.stage_all)
  map(cbuf, "n", km.unstage_all, actions.unstage_all)
  map(cbuf, "n", km.discard, actions.discard)
  map(cbuf, "n", km.open_file, function()
    actions.open_file(M.close)
  end)
  map(cbuf, "n", "<CR>", function()
    local entry = actions.current_changes_entry()
    if not entry then
      return
    end
    if entry.kind == "section" then
      actions.toggle_stage()
    elseif entry.kind == "change_file" then
      render.render_diff_for_entry(entry)
      focus_panel("diff_right")
    end
  end)

  -- Graph panel bindings
  local gbuf = state.bufs.graph
  map(gbuf, "n", "<Tab>", actions.preview_current)
  map(gbuf, "n", "<CR>", function() actions.toggle_commit_expand() end)
  map(gbuf, "n", "<Space>", function() actions.toggle_commit_expand() end)
  map(gbuf, "n", "l", function() actions.toggle_commit_expand(true) end)
  map(gbuf, "n", "h", function() actions.toggle_commit_expand(false) end)
  map(gbuf, "n", km.open_file, function()
    actions.open_file(M.close)
  end)
end

local function setup_autocmds()
  state.augroup = vim.api.nvim_create_augroup("CodeGitUI", { clear = true })

  -- Live diff preview on cursor move in Changes panel
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup,
    buffer = state.bufs.changes,
    callback = function()
      local entry = actions.current_changes_entry()
      if entry and entry.kind == "change_file" then
        render.render_diff_for_entry(entry)
      end
    end,
  })

  -- Live diff preview on cursor move in Graph panel
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup,
    buffer = state.bufs.graph,
    callback = function()
      local entry = actions.current_graph_entry()
      if entry and entry.kind == "commit_file" then
        render.render_diff_for_entry(entry)
      end
    end,
  })

  -- Keep both side-by-side diff panes scrolled together (keyboard & mouse)
  local syncing_scroll = false
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = state.augroup,
    callback = function()
      if syncing_scroll or not state.is_open then
        return
      end
      local wl, wr = state.wins.diff_left, state.wins.diff_right
      if not wl or not wr or not vim.api.nvim_win_is_valid(wl) or not vim.api.nvim_win_is_valid(wr) then
        return
      end

      local ev = vim.v.event or {}
      local ev_l = ev[tostring(wl)]
      local ev_r = ev[tostring(wr)]
      local l_changed = ev_l and (ev_l.topline ~= 0 or ev_l.leftcol ~= 0 or ev_l.topfill ~= 0)
      local r_changed = ev_r and (ev_r.topline ~= 0 or ev_r.leftcol ~= 0 or ev_r.topfill ~= 0)
      if not l_changed and not r_changed then
        return
      end

      local cur = vim.api.nvim_get_current_win()
      local src, dst, src_ev
      if cur == wr and r_changed then
        src, dst, src_ev = wr, wl, ev_r
      elseif cur == wl and l_changed then
        src, dst, src_ev = wl, wr, ev_l
      elseif r_changed then
        src, dst, src_ev = wr, wl, ev_r
      else
        src, dst, src_ev = wl, wr, ev_l
      end

      syncing_scroll = true
      pcall(function()
        vim.api.nvim_win_call(src, function()
          vim.cmd("syncbind")
        end)
        if src_ev.leftcol ~= 0 then
          local src_view = vim.api.nvim_win_call(src, vim.fn.winsaveview)
          vim.api.nvim_win_call(dst, function()
            local dst_view = vim.fn.winsaveview()
            if dst_view.leftcol ~= src_view.leftcol then
              dst_view.leftcol = src_view.leftcol
              if dst_view.col < src_view.leftcol then
                dst_view.col = src_view.leftcol
              end
              vim.fn.winrestview(dst_view)
            end
          end)
        end
      end)
      syncing_scroll = false
    end,
  })

  -- Responsive resize when terminal dimensions change
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      if not state.is_open then
        return
      end
      local layout = compute_layout()
      for _, key in ipairs(panel_order) do
        local win = state.wins[key]
        local geo = layout[key]
        if win and vim.api.nvim_win_is_valid(win) and geo then
          pcall(vim.api.nvim_win_set_config, win, {
            relative = "editor",
            row = geo.row,
            col = geo.col,
            width = geo.width,
            height = geo.height,
          })
        end
      end
    end,
  })

  -- Close all panels cleanly if any panel window is closed manually (e.g. :q)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.augroup,
    callback = function(ev)
      if not state.is_open then
        return
      end
      local closed_id = tonumber(ev.match)
      for _, key in ipairs(panel_order) do
        if state.wins[key] == closed_id then
          vim.schedule(M.close)
          return
        end
      end
    end,
  })
end

function M.open()
  if state.is_open then
    return
  end

  local buf_dir = vim.fn.expand("%:p:h")
  local root = git.get_root(buf_dir ~= "" and buf_dir or nil) or git.get_root()
  if not root then
    vim.notify("[CodeGit] Not inside a Git repository", vim.log.levels.WARN)
    return
  end

  state.reset()
  state.is_open = true
  state.root = root
  state.prev_win = vim.api.nvim_get_current_win()
  state.prev_scrollopt = vim.o.scrollopt
  vim.opt.scrollopt:append("hor")

  render.setup_highlights()

  local border = config.options.border
  local layout = compute_layout()

  -- Create buffers
  state.bufs.commit = create_scratch_buf("commit", true)
  state.bufs.changes = create_scratch_buf("changes", false)
  state.bufs.graph = create_scratch_buf("graph", false)
  state.bufs.diff_left = create_scratch_buf("diff-left", false)
  state.bufs.diff_right = create_scratch_buf("diff-right", false)

  vim.bo[state.bufs.commit].filetype = "gitcommit"

  -- Open 5 floating windows
  state.wins.commit = vim.api.nvim_open_win(state.bufs.commit, false, {
    relative = "editor",
    row = layout.commit.row,
    col = layout.commit.col,
    width = layout.commit.width,
    height = layout.commit.height,
    style = "minimal",
    border = border,
    title = " [1] Commit ",
    title_pos = "left",
    footer = " [C] / <C-s> commit ",
    footer_pos = "right",
    zindex = 50,
  })

  state.wins.changes = vim.api.nvim_open_win(state.bufs.changes, true, {
    relative = "editor",
    row = layout.changes.row,
    col = layout.changes.col,
    width = layout.changes.width,
    height = layout.changes.height,
    style = "minimal",
    border = border,
    title = " [2] Changes ",
    title_pos = "left",
    footer = " [s]tage [x]discard [c]ommit [?]help ",
    footer_pos = "left",
    zindex = 50,
  })

  state.wins.graph = vim.api.nvim_open_win(state.bufs.graph, false, {
    relative = "editor",
    row = layout.graph.row,
    col = layout.graph.col,
    width = layout.graph.width,
    height = layout.graph.height,
    style = "minimal",
    border = border,
    title = " [3] Graph ",
    title_pos = "left",
    footer = " [<CR>] open [l/h] fold [b]ranch [z]stash ",
    footer_pos = "left",
    zindex = 50,
  })

  state.wins.diff_left = vim.api.nvim_open_win(state.bufs.diff_left, false, {
    relative = "editor",
    row = layout.diff_left.row,
    col = layout.diff_left.col,
    width = layout.diff_left.width,
    height = layout.diff_left.height,
    style = "minimal",
    border = border,
    title = " [4] Original ",
    title_pos = "left",
    zindex = 50,
  })

  state.wins.diff_right = vim.api.nvim_open_win(state.bufs.diff_right, false, {
    relative = "editor",
    row = layout.diff_right.row,
    col = layout.diff_right.col,
    width = layout.diff_right.width,
    height = layout.diff_right.height,
    style = "minimal",
    border = border,
    title = " [5] Modified ",
    title_pos = "left",
    footer = " [1-5] panel [p/P] pull/push [q] close ",
    footer_pos = "right",
    zindex = 50,
  })

  -- Window options
  vim.wo[state.wins.commit].wrap = true
  vim.wo[state.wins.changes].cursorline = true
  vim.wo[state.wins.changes].wrap = false
  vim.wo[state.wins.graph].cursorline = true
  vim.wo[state.wins.graph].wrap = false

  for _, key in ipairs({ "diff_left", "diff_right" }) do
    local w = state.wins[key]
    vim.wo[w].number = true
    vim.wo[w].wrap = false
    vim.wo[w].cursorline = true
    vim.wo[w].signcolumn = "no"
    vim.wo[w].fillchars = "diff: ,eob: "
  end

  setup_keymaps()
  setup_autocmds()
  actions.refresh()

  -- Move cursor to first file in Changes if present
  local total_lines = vim.api.nvim_buf_line_count(state.bufs.changes)
  for lnum = 1, total_lines do
    local entry = state.changes_lines[lnum]
    if entry and entry.kind == "change_file" then
      pcall(vim.api.nvim_win_set_cursor, state.wins.changes, { lnum, 0 })
      break
    end
  end
end

function M.toggle()
  if state.is_open then
    M.close()
  else
    M.open()
  end
end

return M
