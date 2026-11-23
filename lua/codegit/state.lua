local M = {}

function M.reset()
  M.is_open = false
  M.root = nil
  M.prev_win = nil
  M.branch = { name = "HEAD", upstream = nil, ahead = 0, behind = 0 }
  M.staged = {}
  M.unstaged = {}
  M.commits = {}
  M.collapsed = {
    staged = false,
    unstaged = false,
  }
  M.expanded_commits = {} -- { [hash] = true }
  M.commit_files_cache = {} -- { [hash] = file[] }

  -- Line maps: [1-based line number] = metadata entry
  M.changes_lines = {}
  M.graph_lines = {}

  -- Current diff key to avoid redundant re-renders
  M.current_diff_key = nil

  -- Window & buffer handles
  M.wins = {
    commit = nil,
    changes = nil,
    graph = nil,
    diff_left = nil,
    diff_right = nil,
  }
  M.bufs = {
    commit = nil,
    changes = nil,
    graph = nil,
    diff_left = nil,
    diff_right = nil,
  }
  M.augroup = nil
  M.ns = vim.api.nvim_create_namespace("codegit")
end

M.reset()

return M
