local config = require("codegit.config")
local ui = require("codegit.ui")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

M.open = ui.open
M.close = ui.close
M.toggle = ui.toggle

return M
