local M = {}

---@param args string[]
---@param cwd string
---@return boolean ok, string stdout, string stderr
function M.run(args, cwd)
  local cmd = vim.list_extend({ "git" }, args)
  local res = vim.system(cmd, { cwd = cwd, text = false }):wait()
  local stdout = res.stdout or ""
  local stderr = res.stderr or ""
  return res.code == 0, stdout, stderr
end

---@param args string[]
---@param cwd string
---@param cb fun(ok: boolean, stdout: string, stderr: string)
function M.run_async(args, cwd, cb)
  local cmd = vim.list_extend({ "git" }, args)
  vim.system(cmd, { cwd = cwd, text = false }, function(res)
    vim.schedule(function()
      cb(res.code == 0, res.stdout or "", res.stderr or "")
    end)
  end)
end

---@param start_dir? string
---@return string|nil
function M.get_root(start_dir)
  local dir = start_dir or vim.fn.getcwd()
  local ok, out = M.run({ "rev-parse", "--show-toplevel" }, dir)
  if not ok then
    return nil
  end
  return vim.trim(out)
end

---@param line string
---@return { name: string, upstream: string|nil, ahead: number, behind: number }
local function parse_branch_header(line)
  local info = { name = "HEAD", upstream = nil, ahead = 0, behind = 0 }
  local rest = line:gsub("^##%s*", "")

  local init_branch = rest:match("^No commits yet on (.+)$")
  if init_branch then
    info.name = init_branch
    return info
  end

  local head_part, brackets = rest:match("^(.-)%s*%[(.-)%]$")
  if not head_part then
    head_part = rest
  end

  local local_b, remote_b = head_part:match("^([^%.]+)%.%.%.(.+)$")
  if local_b then
    info.name = local_b
    info.upstream = remote_b
  else
    info.name = head_part
  end

  if brackets then
    info.ahead = tonumber(brackets:match("ahead (%d+)")) or 0
    info.behind = tonumber(brackets:match("behind (%d+)")) or 0
  end

  return info
end

---@param cwd string
---@return { branch: table, staged: table[], unstaged: table[] }
function M.status(cwd)
  local ok, out = M.run({ "status", "--porcelain=v1", "-z", "-b" }, cwd)
  local result = {
    branch = { name = "HEAD", upstream = nil, ahead = 0, behind = 0 },
    staged = {},
    unstaged = {},
  }
  if not ok or out == "" then
    return result
  end

  local tokens = vim.split(out, "\0", { plain = true })
  local i = 1
  while i <= #tokens do
    local tok = tokens[i]
    if tok ~= "" then
      if vim.startswith(tok, "## ") then
        result.branch = parse_branch_header(tok)
      elseif #tok >= 4 then
        local x = tok:sub(1, 1)
        local y = tok:sub(2, 2)
        local path = tok:sub(4)
        local orig_path = nil

        if x == "R" or x == "C" or y == "R" or y == "C" then
          i = i + 1
          orig_path = tokens[i]
        end

        if x == "?" and y == "?" then
          table.insert(result.unstaged, {
            path = path,
            status = "U",
            raw_status = "??",
            staged = false,
            untracked = true,
          })
        else
          if x ~= " " and x ~= "?" then
            table.insert(result.staged, {
              path = path,
              orig_path = orig_path,
              status = x,
              raw_status = x .. y,
              staged = true,
              untracked = false,
            })
          end
          if y ~= " " and y ~= "?" then
            table.insert(result.unstaged, {
              path = path,
              orig_path = orig_path,
              status = y,
              raw_status = x .. y,
              staged = false,
              untracked = false,
            })
          end
        end
      end
    end
    i = i + 1
  end

  return result
end

---@param cwd string
---@param path string
function M.stage(cwd, path)
  return M.run({ "add", "--", path }, cwd)
end

---@param cwd string
function M.stage_all(cwd)
  return M.run({ "add", "-A" }, cwd)
end

---@param cwd string
---@param path string
function M.unstage(cwd, path)
  local ok, out, err = M.run({ "restore", "--staged", "--", path }, cwd)
  if not ok then
    -- Fallback for repos with no commits yet
    ok, out, err = M.run({ "rm", "--cached", "--", path }, cwd)
  end
  return ok, out, err
end

---@param cwd string
function M.unstage_all(cwd)
  local ok, out, err = M.run({ "reset", "HEAD" }, cwd)
  if not ok then
    ok, out, err = M.run({ "rm", "--cached", "-r", "." }, cwd)
  end
  return ok, out, err
end

---@param cwd string
---@param item table
function M.discard(cwd, item)
  if item.untracked then
    local full = cwd .. "/" .. item.path
    local ok = vim.fn.delete(full, "rf") == 0
    return ok, "", ok and "" or ("Failed to delete " .. item.path)
  end
  return M.run({ "checkout", "--", item.path }, cwd)
end

---@param cwd string
---@param message string
function M.commit(cwd, message)
  return M.run({ "commit", "-m", message }, cwd)
end

---@param cwd string
---@param limit? number
---@return table[]
function M.log(cwd, limit)
  local n = tostring(limit or 50)
  local sep = "\x1f"
  local fmt = "%H" .. sep .. "%h" .. sep .. "%an" .. sep .. "%s" .. sep .. "%D" .. sep .. "%P"
  local ok, out = M.run({ "log", "--all", "--topo-order", "-n", n, "--decorate=short", "--format=" .. fmt }, cwd)
  if not ok or out == "" then
    return {}
  end

  local commits = {}
  for line in out:gmatch("[^\r\n]+") do
    local parts = vim.split(line, sep, { plain = true })
    if #parts >= 4 then
      local refs = {}
      if parts[5] and parts[5] ~= "" then
        for ref in parts[5]:gmatch("[^,]+") do
          local trimmed = vim.trim(ref)
          if trimmed ~= "" then
            table.insert(refs, trimmed)
          end
        end
      end
      local parents = {}
      if parts[6] and parts[6] ~= "" then
        for p in parts[6]:gmatch("%S+") do
          table.insert(parents, p)
        end
      end
      table.insert(commits, {
        hash = parts[1],
        short_hash = parts[2],
        author = parts[3],
        subject = parts[4],
        refs = refs,
        parents = parents,
      })
    end
  end
  return commits
end

---@param cwd string
---@param hash string
---@return table[]
function M.commit_files(cwd, hash)
  local ok, out = M.run(
    { "diff-tree", "--no-commit-id", "--name-status", "-r", "--root", "-m", "--first-parent", "-z", hash },
    cwd
  )
  if not ok or out == "" then
    return {}
  end

  local tokens = vim.split(out, "\0", { plain = true })
  local files = {}
  local i = 1
  while i <= #tokens do
    local status = tokens[i]
    if status and status ~= "" then
      local code = status:sub(1, 1)
      if code == "R" or code == "C" then
        local old_path = tokens[i + 1]
        local new_path = tokens[i + 2]
        if new_path then
          table.insert(files, {
            status = code,
            path = new_path,
            orig_path = old_path,
            commit = hash,
          })
        end
        i = i + 3
      else
        local path = tokens[i + 1]
        if path then
          table.insert(files, {
            status = code,
            path = path,
            commit = hash,
          })
        end
        i = i + 2
      end
    else
      i = i + 1
    end
  end
  return files
end

---@param data string
---@return boolean
local function is_binary(data)
  return data:find("\0", 1, true) ~= nil
end

---@param data string
---@return string[]
local function split_lines(data)
  if data == "" then
    return {}
  end
  data = data:gsub("\r\n", "\n")
  if data:sub(-1) == "\n" then
    data = data:sub(1, -2)
  end
  return vim.split(data, "\n", { plain = true })
end

---@param cwd string
---@param ref string e.g. "HEAD", "", "<hash>", "<hash>~1"
---@param path string
---@return string[] lines, boolean binary
function M.show_file(cwd, ref, path)
  local spec = (ref or "") .. ":" .. path
  local ok, out = M.run({ "show", spec }, cwd)
  if not ok then
    return {}, false
  end
  if is_binary(out) then
    return { "[Binary file]" }, true
  end
  return split_lines(out), false
end

---@param cwd string
---@param path string
---@return string[] lines, boolean binary
function M.read_worktree_file(cwd, path)
  local full = cwd .. "/" .. path
  if vim.fn.filereadable(full) == 0 then
    return {}, false
  end
  local f = io.open(full, "rb")
  if not f then
    return {}, false
  end
  local data = f:read("*a") or ""
  f:close()
  if is_binary(data) then
    return { "[Binary file]" }, true
  end
  return split_lines(data), false
end

---@param cwd string
---@return string[]
function M.branches(cwd)
  local ok, out = M.run({ "branch", "--format=%(refname:short)" }, cwd)
  if not ok or out == "" then
    return {}
  end
  local list = {}
  for line in out:gmatch("[^\r\n]+") do
    local b = vim.trim(line)
    if b ~= "" then
      table.insert(list, b)
    end
  end
  return list
end

---@param cwd string
---@param name string
---@param create? boolean
function M.checkout(cwd, name, create)
  if create then
    return M.run({ "checkout", "-b", name }, cwd)
  end
  return M.run({ "checkout", name }, cwd)
end

---@param cwd string
---@return table[]
function M.stash_list(cwd)
  local ok, out = M.run({ "stash", "list", "--format=%gd%x1f%gs" }, cwd)
  if not ok or out == "" then
    return {}
  end
  local items = {}
  for line in out:gmatch("[^\r\n]+") do
    local ref, msg = line:match("^(.-)\x1f(.*)$")
    if ref then
      table.insert(items, { ref = ref, message = msg })
    end
  end
  return items
end

---@param cwd string
---@param msg? string
function M.stash_push(cwd, msg)
  local args = { "stash", "push", "-u" }
  if msg and msg ~= "" then
    table.insert(args, "-m")
    table.insert(args, msg)
  end
  return M.run(args, cwd)
end

---@param cwd string
---@param ref? string
function M.stash_pop(cwd, ref)
  local args = { "stash", "pop" }
  if ref then
    table.insert(args, ref)
  end
  return M.run(args, cwd)
end

---@param cwd string
---@param ref? string
function M.stash_apply(cwd, ref)
  local args = { "stash", "apply" }
  if ref then
    table.insert(args, ref)
  end
  return M.run(args, cwd)
end

---@param cwd string
---@param ref string
function M.stash_drop(cwd, ref)
  return M.run({ "stash", "drop", ref }, cwd)
end

return M
