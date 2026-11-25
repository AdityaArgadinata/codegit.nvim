local M = {}

M.defaults = {
  border = "rounded",
  width_ratio = 1.0,
  height_ratio = 1.0,
  sidebar_ratio = 0.25,
  sidebar_min_width = 32,
  sidebar_max_width = 46,
  commit_height = 3,
  changes_ratio = 0.42,
  graph_limit = 50,
  keymaps = {
    close = "q",
    refresh = "r",
    help = "?",
    toggle_stage = "s",
    toggle_stage_alt = "<Space>",
    stage_all = "S",
    unstage_all = "U",
    discard = "x",
    commit_focus = "c",
    commit_submit_normal = "C",
    commit_submit = "<C-s>",
    commit_submit_alt = "<C-CR>",
    open_file = "o",
    pull = "p",
    push = "P",
    fetch = "f",
    branch = "b",
    stash = "z",
    next_panel = "<Tab>",
    prev_panel = "<S-Tab>",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
