# codegit.nvim

VSCode-style Source Control floating UI for Neovim — zero dependencies, pure Lua, built for Neovim 0.10+.

## Layout

- **Left sidebar**
  - **`[1] Commit`** (top): write commit messages and submit with `<C-s>` or `<C-CR>`
  - **`[2] Changes`** (middle): collapsible *Staged Changes* and *Changes* (including untracked) with right-aligned status badges
  - **`[3] Graph`** (bottom): commit history across branches with author names, branch refs, and expandable commit file lists (including merge commits)
- **Right area**
  - **`[4] Original` & `[5] Modified`**: native synchronized side-by-side diff (vertical & horizontal scroll sync) with filetype syntax highlighting for working tree changes, staged changes, and historical commits

## Installation (`lazy.nvim`)

```lua
{
  "AdityaArgadinata/codegit.nvim",
  cmd = "CodeGit",
  keys = {
    { "<leader>gg", "<cmd>CodeGit<cr>", desc = "CodeGit" },
  },
  opts = {},
}
```

## Keymaps

| Context | Key | Action |
| --- | --- | --- |
| Changes | `<Tab>` | Preview diff on the right (keeps focus) |
| Changes | `s` / `<Space>` | Toggle stage/unstage (or collapse section) |
| Changes | `S` / `U` | Stage all / Unstage all |
| Changes | `x` | Discard file changes (with confirmation) |
| Changes | `o` / `<CR>` | Open file in editor |
| Graph | `<Tab>` | Expand commit or preview file diff (keeps focus) |
| Graph | `<CR>` / `<Space>` | Expand/collapse commit or focus diff on a commit file |
| Graph | `l` / `h` | Expand / collapse commit |
| Graph | `o` | Open file in editor (or commit snapshot if missing on disk) |
| Commit | `c` / `1` | Focus commit message box |
| Commit | `<C-s>` / `<C-CR>` | Submit commit |
| Sidebar | `p` / `P` / `f` | Pull / Push / Fetch |
| Sidebar | `b` | Branch switcher / create branch |
| Sidebar | `z` | Stash menu (save / pop / apply / drop) |
| Global | `1` – `5` | Jump directly to panel `[1]` Commit, `[2]` Changes, `[3]` Graph, `[4]` Original, `[5]` Modified |
| Global | `<Tab>` / `<S-Tab>` | Cycle panels (`<C-h/j/k/l>` also supported) |
| Global | `r` | Refresh |
| Global | `?` | Show keymap help |
| Global | `q` / `<Esc>` | Close |
