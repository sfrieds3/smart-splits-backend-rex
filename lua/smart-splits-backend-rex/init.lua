-- smart-splits.nvim backend for Rex (protocol 3.0.0). Protocol and module structure adapted from
-- smart-splits-nvim/backend-template (MIT).
local rex = require("smart-splits-backend-rex.rex")
local M = { name = "rex", protocol_version = "3.0.0" }
local options = { enable = true, timeout_ms = 500 }

function M.setup(opts)
  options = vim.tbl_deep_extend("force", { enable = true, timeout_ms = 500 }, opts or {})
end

function M.detect()
  return options.enable
    and type(vim.env.REX_SESSION) == "string"
    and vim.env.REX_SESSION ~= ""
    and type(vim.env.REX_BLOCK) == "string"
    and vim.env.REX_BLOCK ~= ""
    and vim.fn.executable("rex") == 1
end

function M.move(direction, opts)
  return M.detect() and rex.move(direction, opts or {}, options)
end

function M.resize(direction, opts)
  return M.detect() and rex.resize(direction, opts or {}, options)
end

function M.cycle(direction)
  local wins = vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
  local step = direction == "previous" and -1 or 1
  local index = vim.fn.index(wins, vim.api.nvim_get_current_win()) + 1
  if wins[index + step] then
    return vim.api.nvim_set_current_win(wins[index + step])
  end
  if index > 0 and not vim.env.TMUX and M.detect() and rex.cycle(direction, options) then
    return
  end
  vim.api.nvim_set_current_win(wins[step > 0 and 1 or #wins])
end

function M.health()
  if M.detect() then
    vim.health.ok("Rex environment and CLI found (server availability checked on use)")
  else
    vim.health.warn("Rex requires REX_SESSION, REX_BLOCK, and rex on PATH")
  end
end

return M
