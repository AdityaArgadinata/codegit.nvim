local git = require("codegit.git")
local state = require("codegit.state")

local M = {}

function M.setup_highlights()
  local links = {
    CodeGitHeader = "Title",
    CodeGitCount = "Number",
    CodeGitFile = "Normal",
    CodeGitDir = "Comment",
    CodeGitModified = "DiagnosticWarn",
    CodeGitAdded = "DiagnosticOk",
    CodeGitDeleted = "DiagnosticError",
    CodeGitRenamed = "DiagnosticInfo",
    CodeGitGraphDot = "Function",
    CodeGitGraphLine = "Comment",
    CodeGitHash = "Constant",
    CodeGitAuthor = "Comment",
    CodeGitRef = "DiagnosticInfo",
    CodeGitHint = "Comment",
  }
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

---@param status string
---@return string hl
local function status_hl(status)
  if status == "A" or status == "U" or status == "?" then
    return "CodeGitAdded"
  elseif status == "D" then
    return "CodeGitDeleted"
  elseif status == "R" or status == "C" then
    return "CodeGitRenamed"
  end
  return "CodeGitModified"
end

---@param path string
---@return string filename, string dir
local function split_path(path)
  local dir, name = path:match("^(.*)/([^/]+)$")
  if not name then
    return path, ""
  end
  return name, dir
end

---@param buf number
---@param lines string[]
local function set_buf_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.update_commit_title()
  local win = state.wins.commit
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local b = state.branch
  local suffix = ""
  if b.ahead > 0 then
    suffix = suffix .. " ↑" .. b.ahead
  end
  if b.behind > 0 then
    suffix = suffix .. " ↓" .. b.behind
  end
  local title = string.format(" [1] Commit (%s%s) ", b.name or "HEAD", suffix)
  vim.api.nvim_win_set_config(win, {
    title = title,
    title_pos = "left",
    footer = " [C] / <C-s> commit ",
    footer_pos = "right",
  })
end

function M.render_changes()
  local buf = state.bufs.changes
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {}
  local line_map = {}
  local extmarks = {}

  local function add_section(key, label, items)
    local icon = state.collapsed[key] and "▸" or "▾"
    local header = string.format("%s %s (%d)", icon, label, #items)
    table.insert(lines, header)
    local lnum = #lines
    line_map[lnum] = { kind = "section", section = key }
    table.insert(extmarks, {
      line = lnum - 1,
      col = 0,
      end_col = #header,
      hl = "CodeGitHeader",
    })

    if not state.collapsed[key] then
      if #items == 0 then
        local empty = "  (none)"
        table.insert(lines, empty)
        table.insert(extmarks, {
          line = #lines - 1,
          col = 0,
          end_col = #empty,
          hl = "CodeGitHint",
        })
      else
        for _, item in ipairs(items) do
          local name, dir = split_path(item.path)
          local text = dir ~= "" and ("  " .. name .. " " .. dir) or ("  " .. name)
          table.insert(lines, text)
          local row = #lines
          line_map[row] = { kind = "change_file", item = item }

          table.insert(extmarks, {
            line = row - 1,
            col = 2,
            end_col = 2 + #name,
            hl = "CodeGitFile",
          })
          if dir ~= "" then
            table.insert(extmarks, {
              line = row - 1,
              col = 2 + #name + 1,
              end_col = #text,
              hl = "CodeGitDir",
            })
          end
          table.insert(extmarks, {
            line = row - 1,
            virt_text = { { " " .. item.status .. " ", status_hl(item.status) } },
            virt_text_pos = "right_align",
          })
        end
      end
    end
  end

  add_section("staged", "Staged Changes", state.staged)
  add_section("unstaged", "Changes", state.unstaged)

  state.changes_lines = line_map
  set_buf_lines(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)

  for _, em in ipairs(extmarks) do
    if em.virt_text then
      vim.api.nvim_buf_set_extmark(buf, state.ns, em.line, 0, {
        virt_text = em.virt_text,
        virt_text_pos = em.virt_text_pos,
      })
    else
      vim.api.nvim_buf_set_extmark(buf, state.ns, em.line, em.col, {
        end_col = em.end_col,
        hl_group = em.hl,
      })
    end
  end
end

function M.render_graph()
  local buf = state.bufs.graph
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {}
  local line_map = {}
  local extmarks = {}

  if #state.commits == 0 then
    local empty = "  (no commits yet)"
    table.insert(lines, empty)
    table.insert(extmarks, {
      line = 0,
      col = 0,
      end_col = #empty,
      hl = "CodeGitHint",
    })
  else
    for _, c in ipairs(state.commits) do
      local expanded = state.expanded_commits[c.hash] == true
      local dot = expanded and "◉" or "●"
      local text = string.format("%s %s %s %s", dot, c.subject, c.short_hash, c.author)
      table.insert(lines, text)
      local row = #lines
      line_map[row] = { kind = "commit", commit = c }

      local dot_bytes = #dot
      local subj_start = dot_bytes + 1
      local subj_end = subj_start + #c.subject
      local hash_start = subj_end + 1
      local hash_end = hash_start + #c.short_hash
      local author_start = hash_end + 1
      local author_end = author_start + #c.author

      table.insert(extmarks, {
        line = row - 1,
        col = 0,
        end_col = dot_bytes,
        hl = "CodeGitGraphDot",
      })
      table.insert(extmarks, {
        line = row - 1,
        col = subj_start,
        end_col = subj_end,
        hl = "CodeGitFile",
      })
      table.insert(extmarks, {
        line = row - 1,
        col = hash_start,
        end_col = hash_end,
        hl = "CodeGitHash",
      })
      table.insert(extmarks, {
        line = row - 1,
        col = author_start,
        end_col = author_end,
        hl = "CodeGitAuthor",
      })

      -- Right-aligned ref pills (up to 2)
      if #c.refs > 0 then
        local virt = {}
        local count = 0
        for _, r in ipairs(c.refs) do
          local clean = r:gsub("^HEAD %-> ", "")
          if clean ~= "origin/HEAD" then
            table.insert(virt, { " " .. clean .. " ", "CodeGitRef" })
            count = count + 1
            if count >= 2 then
              break
            end
          end
        end
        if #virt > 0 then
          table.insert(extmarks, {
            line = row - 1,
            virt_text = virt,
            virt_text_pos = "right_align",
          })
        end
      end

      if expanded then
        local files = state.commit_files_cache[c.hash] or {}
        if #files == 0 then
          local none = "│  (no files)"
          table.insert(lines, none)
          table.insert(extmarks, {
            line = #lines - 1,
            col = 0,
            end_col = #"│",
            hl = "CodeGitGraphLine",
          })
          table.insert(extmarks, {
            line = #lines - 1,
            col = #"│",
            end_col = #none,
            hl = "CodeGitHint",
          })
        else
          for _, f in ipairs(files) do
            local name, dir = split_path(f.path)
            local ftext = dir ~= "" and ("│  " .. name .. " " .. dir) or ("│  " .. name)
            table.insert(lines, ftext)
            local frow = #lines
            line_map[frow] = { kind = "commit_file", file = f, commit = c }

            local bar_bytes = #"│"
            table.insert(extmarks, {
              line = frow - 1,
              col = 0,
              end_col = bar_bytes,
              hl = "CodeGitGraphLine",
            })
            table.insert(extmarks, {
              line = frow - 1,
              col = bar_bytes + 2,
              end_col = bar_bytes + 2 + #name,
              hl = "CodeGitFile",
            })
            if dir ~= "" then
              table.insert(extmarks, {
                line = frow - 1,
                col = bar_bytes + 2 + #name + 1,
                end_col = #ftext,
                hl = "CodeGitDir",
              })
            end
            table.insert(extmarks, {
              line = frow - 1,
              virt_text = { { " " .. f.status .. " ", status_hl(f.status) } },
              virt_text_pos = "right_align",
            })
          end
        end
      end
    end
  end

  state.graph_lines = line_map
  set_buf_lines(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)

  for _, em in ipairs(extmarks) do
    if em.virt_text then
      vim.api.nvim_buf_set_extmark(buf, state.ns, em.line, 0, {
        virt_text = em.virt_text,
        virt_text_pos = em.virt_text_pos,
      })
    else
      vim.api.nvim_buf_set_extmark(buf, state.ns, em.line, em.col, {
        end_col = em.end_col,
        hl_group = em.hl,
      })
    end
  end
end

---@param win number
---@param buf number
---@param lines string[]
---@param ft string|nil
---@param title string
local function set_diff_pane(win, buf, lines, ft, title)
  if not win or not vim.api.nvim_win_is_valid(win) or not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  set_buf_lines(buf, lines)
  vim.bo[buf].filetype = ft or ""
  vim.api.nvim_win_set_config(win, {
    title = " " .. title .. " ",
    title_pos = "left",
  })
end

---@param left_lines string[]
---@param right_lines string[]
---@return number first_diff_line
local function find_first_diff_line(left_lines, right_lines)
  local max_n = math.max(#left_lines, #right_lines)
  for i = 1, max_n do
    if left_lines[i] ~= right_lines[i] then
      return i
    end
  end
  return 1
end

function M.clear_diff(message)
  state.current_diff_key = nil
  local msg = message and { "", "  " .. message } or { "" }
  set_diff_pane(state.wins.diff_left, state.bufs.diff_left, msg, "", "[4] Original")
  set_diff_pane(state.wins.diff_right, state.bufs.diff_right, msg, "", "[5] Modified")
end

---@param entry table|nil
function M.render_diff_for_entry(entry)
  if not entry then
    return
  end
  local wl, wr = state.wins.diff_left, state.wins.diff_right
  local bl, br = state.bufs.diff_left, state.bufs.diff_right
  if not wl or not wr or not vim.api.nvim_win_is_valid(wl) or not vim.api.nvim_win_is_valid(wr) then
    return
  end

  local left_lines, right_lines = {}, {}
  local left_title, right_title = "Original", "Modified"
  local path = nil
  local diff_key = nil

  if entry.kind == "change_file" then
    local item = entry.item
    path = item.path
    local name = select(1, split_path(path))
    diff_key = "change:" .. (item.staged and "S:" or "U:") .. path .. ":" .. item.status

    if item.untracked then
      left_lines = {}
      right_lines = git.read_worktree_file(state.root, path)
      left_title = name .. " (new file)"
      right_title = name .. " (working tree)"
    elseif item.staged then
      local head_path = item.orig_path or path
      left_lines = git.show_file(state.root, "HEAD", head_path)
      right_lines = git.show_file(state.root, "", path)
      left_title = name .. " (HEAD)"
      right_title = name .. " (staged)"
    else
      -- Unstaged working tree vs index
      left_lines = git.show_file(state.root, "", path)
      if item.status == "D" then
        right_lines = {}
        right_title = name .. " (deleted)"
      else
        right_lines = git.read_worktree_file(state.root, path)
        right_title = name .. " (working tree)"
      end
      left_title = name .. " (index)"
    end
  elseif entry.kind == "commit_file" then
    local f = entry.file
    local c = entry.commit
    path = f.path
    local name = select(1, split_path(path))
    diff_key = "commit:" .. c.hash .. ":" .. path

    local parent_hash = c.parents and c.parents[1] or nil
    if parent_hash then
      local old_path = f.orig_path or path
      left_lines = git.show_file(state.root, parent_hash, old_path)
      left_title = string.format("%s (%s)", name, parent_hash:sub(1, 7))
    else
      left_lines = {}
      left_title = name .. " (root)"
    end

    if f.status == "D" then
      right_lines = {}
      right_title = string.format("%s (%s deleted)", name, c.short_hash)
    else
      right_lines = git.show_file(state.root, c.hash, path)
      right_title = string.format("%s (%s)", name, c.short_hash)
    end
  else
    return
  end

  if diff_key == state.current_diff_key then
    return
  end
  state.current_diff_key = diff_key

  local ft = path and vim.filetype.match({ filename = path }) or ""
  set_diff_pane(wl, bl, left_lines, ft, "[4] " .. left_title)
  set_diff_pane(wr, br, right_lines, ft, "[5] " .. right_title)

  -- Enable synchronized native diff on both floating diff panes
  for _, win in ipairs({ wl, wr }) do
    vim.wo[win].diff = true
    vim.wo[win].scrollbind = true
    vim.wo[win].cursorbind = true
    vim.wo[win].foldenable = false
  end
  pcall(vim.cmd, "diffupdate")

  -- Jump to first changed line for immediate context and sync both panes
  local first_line = find_first_diff_line(left_lines, right_lines)
  local l_max = math.max(1, #left_lines)
  local r_max = math.max(1, #right_lines)
  pcall(vim.api.nvim_win_set_cursor, wl, { math.min(first_line, l_max), 0 })
  pcall(vim.api.nvim_win_set_cursor, wr, { math.min(first_line, r_max), 0 })
  for _, win in ipairs({ wl, wr }) do
    vim.api.nvim_win_call(win, function()
      pcall(vim.cmd, "normal! zz")
    end)
  end
  vim.api.nvim_win_call(wl, function()
    pcall(vim.cmd, "syncbind")
  end)
end

return M
