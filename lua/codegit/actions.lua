local config = require("codegit.config")
local git = require("codegit.git")
local render = require("codegit.render")
local state = require("codegit.state")

local M = {}

---@param msg string
---@param level? number
local function notify(msg, level)
  vim.notify("[CodeGit] " .. msg, level or vim.log.levels.INFO)
end

---@return table|nil
function M.current_changes_entry()
  local win = state.wins.changes
  if not win or not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  return state.changes_lines[lnum]
end

---@return table|nil
function M.current_graph_entry()
  local win = state.wins.graph
  if not win or not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  return state.graph_lines[lnum]
end

function M.refresh()
  if not state.is_open or not state.root then
    return
  end

  local st = git.status(state.root)
  state.branch = st.branch
  state.staged = st.staged
  state.unstaged = st.unstaged
  state.commits = git.log(state.root, config.options.graph_limit)
  state.current_diff_key = nil

  render.update_commit_title()
  render.render_changes()
  render.render_graph()

  -- Preview first available file if nothing is currently pointed at
  local cur_win = vim.api.nvim_get_current_win()
  local entry = nil
  if cur_win == state.wins.graph then
    entry = M.current_graph_entry()
  else
    entry = M.current_changes_entry()
  end

  if entry and (entry.kind == "change_file" or entry.kind == "commit_file") then
    render.render_diff_for_entry(entry)
  else
    -- Fall back to first changed file so diff pane isn't blank
    local first = state.staged[1] or state.unstaged[1]
    if first then
      render.render_diff_for_entry({ kind = "change_file", item = first })
    else
      render.clear_diff("Select a file in Changes or expand a commit in Graph to view diff")
    end
  end
end

function M.toggle_stage()
  local entry = M.current_changes_entry()
  if not entry then
    return
  end

  if entry.kind == "section" then
    state.collapsed[entry.section] = not state.collapsed[entry.section]
    render.render_changes()
    return
  end

  if entry.kind ~= "change_file" then
    return
  end

  local item = entry.item
  local ok, _, err
  if item.staged then
    ok, _, err = git.unstage(state.root, item.path)
  else
    ok, _, err = git.stage(state.root, item.path)
  end

  if not ok then
    notify("Git error: " .. vim.trim(err), vim.log.levels.ERROR)
    return
  end
  M.refresh()
end

function M.stage_all()
  local ok, _, err = git.stage_all(state.root)
  if not ok then
    notify("Stage all failed: " .. vim.trim(err), vim.log.levels.ERROR)
    return
  end
  M.refresh()
end

function M.unstage_all()
  local ok, _, err = git.unstage_all(state.root)
  if not ok then
    notify("Unstage all failed: " .. vim.trim(err), vim.log.levels.ERROR)
    return
  end
  M.refresh()
end

function M.discard()
  local entry = M.current_changes_entry()
  if not entry or entry.kind ~= "change_file" then
    return
  end
  local item = entry.item
  if item.staged then
    notify("Unstage the file first before discarding", vim.log.levels.WARN)
    return
  end

  local label = item.untracked and ("Delete untracked file '" .. item.path .. "'?")
    or ("Discard changes in '" .. item.path .. "'?")
  local choice = vim.fn.confirm(label, "&No\n&Yes", 1)
  if choice ~= 2 then
    return
  end

  local ok, _, err = git.discard(state.root, item)
  if not ok then
    notify("Discard failed: " .. vim.trim(err), vim.log.levels.ERROR)
    return
  end
  notify("Discarded " .. item.path)
  M.refresh()
end

function M.focus_commit()
  local win = state.wins.commit
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    vim.cmd("startinsert")
  end
end

function M.submit_commit()
  local buf = state.bufs.commit
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local msg = vim.trim(table.concat(lines, "\n"))
  if msg == "" then
    notify("Commit message is empty", vim.log.levels.WARN)
    return
  end

  if #state.staged == 0 then
    if #state.unstaged == 0 then
      notify("Nothing to commit", vim.log.levels.WARN)
      return
    end
    local choice = vim.fn.confirm("No staged changes. Stage all and commit?", "&Yes\n&No", 1)
    if choice ~= 1 then
      return
    end
    local ok_stage, _, err_stage = git.stage_all(state.root)
    if not ok_stage then
      notify("Stage all failed: " .. vim.trim(err_stage), vim.log.levels.ERROR)
      return
    end
  end

  local ok, out, err = git.commit(state.root, msg)
  if not ok then
    notify("Commit failed: " .. vim.trim(err ~= "" and err or out), vim.log.levels.ERROR)
    return
  end

  -- Exit insert mode if active, clear commit box, and focus changes list
  vim.cmd("stopinsert")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  if state.wins.changes and vim.api.nvim_win_is_valid(state.wins.changes) then
    vim.api.nvim_set_current_win(state.wins.changes)
  end

  notify("Committed: " .. msg:match("^[^\n]+"))
  M.refresh()
end

function M.pull()
  notify("Pulling...")
  git.run_async({ "pull" }, state.root, function(ok, out, err)
    if not ok then
      notify("Pull failed: " .. vim.trim(err ~= "" and err or out), vim.log.levels.ERROR)
      return
    end
    notify("Pull complete")
    M.refresh()
  end)
end

function M.push()
  notify("Pushing...")
  git.run_async({ "push" }, state.root, function(ok, out, err)
    if not ok then
      notify("Push failed: " .. vim.trim(err ~= "" and err or out), vim.log.levels.ERROR)
      return
    end
    notify("Push complete")
    M.refresh()
  end)
end

function M.fetch()
  notify("Fetching...")
  git.run_async({ "fetch", "--all", "--prune" }, state.root, function(ok, out, err)
    if not ok then
      notify("Fetch failed: " .. vim.trim(err ~= "" and err or out), vim.log.levels.ERROR)
      return
    end
    notify("Fetch complete")
    M.refresh()
  end)
end

function M.branch_menu()
  local branches = git.branches(state.root)
  local items = { "+ Create new branch..." }
  for _, b in ipairs(branches) do
    local prefix = (b == state.branch.name) and "* " or "  "
    table.insert(items, prefix .. b)
  end

  vim.ui.select(items, { prompt = "Switch or create branch:" }, function(choice)
    if not choice then
      return
    end
    if choice == "+ Create new branch..." then
      vim.ui.input({ prompt = "New branch name: " }, function(name)
        name = name and vim.trim(name) or ""
        if name == "" then
          return
        end
        local ok, _, err = git.checkout(state.root, name, true)
        if not ok then
          notify("Create branch failed: " .. vim.trim(err), vim.log.levels.ERROR)
          return
        end
        notify("Switched to new branch " .. name)
        M.refresh()
      end)
    else
      local target = choice:gsub("^[*%s]+", "")
      if target == state.branch.name then
        return
      end
      local ok, _, err = git.checkout(state.root, target, false)
      if not ok then
        notify("Checkout failed: " .. vim.trim(err), vim.log.levels.ERROR)
        return
      end
      notify("Switched to " .. target)
      M.refresh()
    end
  end)
end

function M.stash_menu()
  local actions = {
    "Save stash (include untracked)",
    "Pop stash...",
    "Apply stash...",
    "Drop stash...",
  }

  vim.ui.select(actions, { prompt = "Stash action:" }, function(choice)
    if not choice then
      return
    end

    if vim.startswith(choice, "Save") then
      vim.ui.input({ prompt = "Stash message (optional): " }, function(msg)
        if msg == nil then
          return
        end
        local ok, _, err = git.stash_push(state.root, vim.trim(msg))
        if not ok then
          notify("Stash save failed: " .. vim.trim(err), vim.log.levels.ERROR)
          return
        end
        notify("Stash saved")
        M.refresh()
      end)
      return
    end

    local stashes = git.stash_list(state.root)
    if #stashes == 0 then
      notify("No stashes found", vim.log.levels.WARN)
      return
    end

    local labels = {}
    for _, s in ipairs(stashes) do
      table.insert(labels, s.ref .. ": " .. s.message)
    end

    vim.ui.select(labels, { prompt = choice }, function(sel, idx)
      if not sel or not idx then
        return
      end
      local ref = stashes[idx].ref
      local ok, _, err
      if vim.startswith(choice, "Pop") then
        ok, _, err = git.stash_pop(state.root, ref)
      elseif vim.startswith(choice, "Apply") then
        ok, _, err = git.stash_apply(state.root, ref)
      elseif vim.startswith(choice, "Drop") then
        ok, _, err = git.stash_drop(state.root, ref)
      end

      if not ok then
        notify("Stash action failed: " .. vim.trim(err), vim.log.levels.ERROR)
        return
      end
      notify("Stash updated (" .. ref .. ")")
      M.refresh()
    end)
  end)
end

function M.toggle_commit_expand(force_state)
  local entry = M.current_graph_entry()
  if not entry then
    return
  end
  if entry.kind == "commit_file" then
    if force_state == false then
      -- Collapse parent commit and move cursor to it
      state.expanded_commits[entry.commit.hash] = nil
      render.render_graph()
      local win = state.wins.graph
      if win and vim.api.nvim_win_is_valid(win) then
        local total = vim.api.nvim_buf_line_count(state.bufs.graph)
        for l = 1, total do
          local e = state.graph_lines[l]
          if e and e.kind == "commit" and e.commit.hash == entry.commit.hash then
            vim.api.nvim_win_set_cursor(win, { l, 0 })
            break
          end
        end
      end
      return
    end
    render.render_diff_for_entry(entry)
    if force_state == nil and state.wins.diff_right and vim.api.nvim_win_is_valid(state.wins.diff_right) then
      vim.api.nvim_set_current_win(state.wins.diff_right)
    end
    return
  end
  if entry.kind ~= "commit" then
    return
  end

  local hash = entry.commit.hash
  local should_expand = force_state
  if should_expand == nil then
    should_expand = not state.expanded_commits[hash]
  end

  if not should_expand then
    state.expanded_commits[hash] = nil
  else
    if not state.commit_files_cache[hash] then
      state.commit_files_cache[hash] = git.commit_files(state.root, hash)
    end
    state.expanded_commits[hash] = true
  end

  local win = state.wins.graph
  local cursor = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_cursor(win) or { 1, 0 }
  render.render_graph()
  if win and vim.api.nvim_win_is_valid(win) then
    local max_line = vim.api.nvim_buf_line_count(state.bufs.graph)
    vim.api.nvim_win_set_cursor(win, { math.min(cursor[1], max_line), 0 })
  end

  if should_expand then
    local files = state.commit_files_cache[hash]
    if files and files[1] then
      render.render_diff_for_entry({ kind = "commit_file", file = files[1], commit = entry.commit })
    end
  end
end

function M.preview_current()
  local cur_win = vim.api.nvim_get_current_win()
  if cur_win == state.wins.changes then
    local entry = M.current_changes_entry()
    if not entry then
      return
    end
    if entry.kind == "section" then
      state.collapsed[entry.section] = not state.collapsed[entry.section]
      render.render_changes()
    elseif entry.kind == "change_file" then
      state.current_diff_key = nil
      render.render_diff_for_entry(entry)
    end
  elseif cur_win == state.wins.graph then
    local entry = M.current_graph_entry()
    if not entry then
      return
    end
    if entry.kind == "commit" then
      M.toggle_commit_expand()
    elseif entry.kind == "commit_file" then
      state.current_diff_key = nil
      render.render_diff_for_entry(entry)
    end
  end
end

---@param close_fn fun()
function M.open_file(close_fn)
  local cur_win = vim.api.nvim_get_current_win()
  local path = nil
  local commit_hash = nil
  if cur_win == state.wins.changes then
    local entry = M.current_changes_entry()
    if entry and entry.kind == "change_file" then
      path = entry.item.path
    end
  elseif cur_win == state.wins.graph then
    local entry = M.current_graph_entry()
    if entry and entry.kind == "commit_file" then
      path = entry.file.path
      commit_hash = entry.commit.hash
    end
  end

  if not path then
    return
  end

  local full = state.root .. "/" .. path
  local root = state.root
  local target_win = state.prev_win

  if vim.fn.filereadable(full) == 1 then
    close_fn()
    if target_win and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end
    vim.cmd.edit(vim.fn.fnameescape(full))
    return
  end

  if commit_hash then
    local lines = git.show_file(root, commit_hash, path)
    close_fn()
    if target_win and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = vim.filetype.match({ filename = path }) or ""
    pcall(vim.api.nvim_buf_set_name, buf, string.format("%s (%s)", path, commit_hash:sub(1, 7)))
    vim.api.nvim_win_set_buf(0, buf)
    return
  end

  notify("File does not exist on disk: " .. path, vim.log.levels.WARN)
end

function M.show_help()
  local lines = {
    " CodeGit Keymaps",
    " ──────────────────────────────────────────",
    "  Changes Panel",
    "    <Tab>        Preview diff (keep focus)",
    "    s / <Space>  Stage / Unstage (or fold section)",
    "    S / U        Stage all / Unstage all",
    "    x            Discard file changes",
    "    o / <CR>     Open file in editor",
    "",
    "  Graph Panel",
    "    <Tab>        Expand commit / preview diff (keep focus)",
    "    <CR>         Expand commit / focus diff panel",
    "    l / h        Expand / collapse commit",
    "    o            Open file in editor",
    "",
    "  Commit Box",
    "    c / 1        Focus commit message box",
    "    <C-s>/<C-CR> Submit commit",
    "",
    "  Global (any panel)",
    "    1 - 5        Jump to panel [1]..[5]",
    "    <Tab>/<S-Tab> Switch panel (<C-h/j/k/l> too)",
    "    p / P / f    Pull / Push / Fetch",
    "    b / z        Branch switcher / Stash menu",
    "    r            Refresh",
    "    ?            Toggle this help",
    "    q / <Esc>    Close CodeGit",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 52
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = config.options.border,
    title = " Help ",
    title_pos = "center",
    footer = " Press q or <Esc> to close ",
    footer_pos = "center",
    zindex = 80,
  })

  local function close_help()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close_help, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_help, { buffer = buf, silent = true })
  vim.keymap.set("n", "?", close_help, { buffer = buf, silent = true })
end

return M
