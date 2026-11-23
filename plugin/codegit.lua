if vim.g.loaded_codegit then
  return
end
vim.g.loaded_codegit = true

vim.api.nvim_create_user_command("CodeGit", function()
  require("codegit").toggle()
end, { desc = "Toggle CodeGit VSCode-style Source Control floating UI" })
