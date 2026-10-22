-- The Rex half of smart-splits-backend-rex: key handlers for Rex's Lua config (see README.md).
-- Rex owns these keys at a shell; editors and nested multiplexers own them otherwise.
local default_passthrough = { "nvim", "vim", "tmux", "ssh", "mosh", "mosh-client" }
local passthrough, resize_amount = {}, 3

local function owns_keys(process)
  if type(process) ~= "table" then
    return false
  end
  for _, field in ipairs({ "name", "path", "argv0" }) do
    local name = type(process[field]) == "string" and process[field]:match("([^/]+)$")
    if name and passthrough[name] then
      return true
    end
  end
  return false
end

local function block_call(ctx, method, args)
  return rex.call("com.superlogical.terminal." .. method, {
    session_id = ctx.session_id,
    block_id = ctx.block_id,
    args = args or {},
  })
end

local function find(node, block, axis)
  if type(node) ~= "table" then
    return
  end
  if node.block_id == block then
    return node
  end
  if type(node.split) == "table" then
    for _, side in ipairs({ "before", "after" }) do
      local leaf, border = find(node.split[side], block, axis)
      if leaf then
        return leaf, border or (node.split.direction == axis and node or nil)
      end
    end
  end
end

local function first_block(node)
  if type(node) == "table" then
    return node.block_id or (node.split and (first_block(node.split.before) or first_block(node.split.after)))
  end
end

local function resize(ctx, direction)
  local axis = (direction == "left" or direction == "right") and "horizontal" or "vertical"
  local view = rex.call("session.view", { session_id = ctx.session_id })
  for _, window in ipairs(view and view.windows or {}) do
    if window.window_id == view.active_window_id and window.focused_block_id == ctx.block_id then
      if type(window.zoomed_block_id) == "string" and window.zoomed_block_id ~= "" then
        return false
      end
      for _, layer in ipairs(window.layers or {}) do
        local leaf, border = find(layer.layout, ctx.block_id, axis)
        if leaf and border then
          local size = block_call(ctx, "size")
          local cells = size and (axis == "horizontal" and size.columns or size.rows)
          if not cells or cells <= 0 then
            return false
          end
          local dimension = axis == "horizontal" and 3 or 4
          local sign = (direction == "left" or direction == "up") and -1 or 1
          local delta = resize_amount / cells * leaf.rect[dimension] / border.rect[dimension]
          local result = rex.call("session.resize_pane", {
            session_id = ctx.session_id,
            direction = axis,
            before_block_id = first_block(border.split.before),
            after_block_id = first_block(border.split.after),
            ratio = math.max(0.01, math.min(0.99, border.split.ratio + sign * delta)),
          })
          return result ~= nil
        end
      end
    end
  end
  return false
end

local function handler(direction, operation, forwarded)
  return function(ctx)
    if not ctx.session_id or not ctx.block_id then
      return false
    end
    local process = block_call(ctx, "process")
    -- Missing process data/nonterminal blocks must not swallow input.
    if not process or type(process.foreground) ~= "table" then
      return false
    end
    local nested = owns_keys(process.foreground)
    for _, ancestor in ipairs(process.ancestors or {}) do
      nested = nested or owns_keys(ancestor)
    end
    if nested then
      -- Aliases send the Ctrl+Alt/Shift+Fn/Alt+bracket keys that Neovim and tmux bind.
      -- Without an alias, the original chord simply passes through unchanged.
      return forwarded ~= nil and block_call(ctx, "write", { data = forwarded }) ~= nil
    end
    if operation == "resize" then
      return resize(ctx, direction)
    end
    if operation == "cycle" then
      return rex.call("session.focus_" .. direction .. "_pane", { session_id = ctx.session_id, wrap = true }) ~= nil
    end
    return rex.call("session.focus_direction", {
      session_id = ctx.session_id,
      direction = direction,
      wrap = true,
    }) ~= nil
  end
end

local navigate = { left = "\27[104;7u", down = "\27[106;7u", up = "\27[107;7u", right = "\27[108;7u" }
local shift_fn = { left = "\27[1;2P", down = "\27[1;2Q", up = "\27[1;2R", right = "\27[1;2S" }
local cycle = { previous = "\27[91;3u", next = "\27[93;3u" }

local M = {}

-- opts.passthrough: more program names that get the keys (added to nvim, vim, tmux, ssh, mosh).
-- opts.resize_amount: cells each resize moves the border by (default 3, like smart-splits).
function M.setup(opts)
  opts = opts or {}
  passthrough = {}
  for _, list in ipairs({ default_passthrough, opts.passthrough or {} }) do
    for _, name in ipairs(list) do
      passthrough[name] = true
    end
  end
  resize_amount = opts.resize_amount or 3
end

-- Handlers to bind with rex.bind. With alias, a nested program gets the key sequence smart-splits binds
-- (Ctrl+Alt+h/j/k/l, Shift+F1-F4, Alt+[ and Alt+]) instead of the original chord.
function M.focus(direction, alias)
  return handler(direction, "move", alias and navigate[direction] or nil)
end

function M.resize(direction, alias)
  return handler(direction, "resize", alias and shift_fn[direction] or nil)
end

function M.cycle(direction, alias)
  return handler(direction, "cycle", alias and cycle[direction] or nil)
end

M.setup()

return M
