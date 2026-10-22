local layout = require("smart-splits-backend-rex.layout")
local M = {}
local axes = { left = "horizontal", right = "horizontal", up = "vertical", down = "vertical" }

local function run(args, options)
  local argv = { "rex", "--autostart=false", "--timeout", options.timeout_ms .. "ms" }
  vim.list_extend(argv, args)
  local ok, result = pcall(function()
    return vim.system(argv, { text = true }):wait(options.timeout_ms)
  end)
  if not ok or result.code ~= 0 then
    return
  end
  local decoded, value = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
  if decoded and type(value) == "table" then
    return value
  end
end

local function api(method, args, options)
  return run({ "api", "call", "-s", vim.env.REX_SESSION, method, vim.json.encode(args or vim.empty_dict()) }, options)
end

-- focus_direction is session-scoped, so never move a different window/pane
-- when an old Neovim instance receives a remote command.
local function context(options)
  local view = api("session.view", nil, options)
  if not view or type(view.revision) ~= "number" then
    return
  end
  for _, window in ipairs(view.windows or {}) do
    if window.window_id == view.active_window_id and window.focused_block_id == vim.env.REX_BLOCK then
      for _, layer in ipairs(window.layers or {}) do
        local leaf, path = layout.find(layer.layout, vim.env.REX_BLOCK)
        if leaf then
          return view, window, leaf, path
        end
      end
    end
  end
end

-- A revision can also change for unrelated concurrent mutations. Verify focus.
local function focus_left_block(view, options)
  local after = api("session.view", nil, options)
  for _, window in ipairs(after and after.windows or {}) do
    if window.window_id == view.active_window_id and after.active_window_id == window.window_id then
      return type(window.focused_block_id) == "string" and window.focused_block_id ~= vim.env.REX_BLOCK
    end
  end
  return false
end

function M.move(direction, opts, options)
  if not axes[direction] then
    return false
  end
  local view = context(options)
  if not view then
    return false
  end
  local result = api("session.focus_direction", { direction = direction, wrap = opts.at_edge == "wrap" }, options)
  if not result or type(result.revision) ~= "number" then
    return false
  end
  if result.revision > view.revision then
    return focus_left_block(view, options)
  end
  if opts.at_edge == "split" then
    local split = api("session.new_split", {
      anchor_block_id = vim.env.REX_BLOCK,
      direction = axes[direction],
      side = (direction == "left" or direction == "up") and "before" or "after",
      layout = { block = { flavor = "com.superlogical.terminal.shell" } },
      focus = true,
    }, options)
    return split ~= nil and type(split.block_ids) == "table" and #split.block_ids > 0
  end
  return false
end

function M.cycle(direction, options)
  if direction ~= "next" and direction ~= "previous" then
    return false
  end
  local view = context(options)
  if not view then
    return false
  end
  local result = api("session.focus_" .. direction .. "_pane", { wrap = true }, options)
  return result ~= nil
    and type(result.revision) == "number"
    and result.revision > view.revision
    and focus_left_block(view, options)
end

function M.resize(direction, opts, options)
  local axis = axes[direction]
  local amount = opts.amount or 3
  if not axis or type(amount) ~= "number" or amount <= 0 or amount ~= amount or amount == math.huge then
    return false
  end
  local view, window, leaf, path = context(options)
  if not view or (type(window.zoomed_block_id) == "string" and window.zoomed_block_id ~= "") then
    return false
  end
  for _, node in ipairs(path) do
    if node.split.direction == axis then
      local size = run({ "block", "call", "-s", vim.env.REX_SESSION, "-b", vim.env.REX_BLOCK, "size", "{}" }, options)
      local dimension = axis == "horizontal" and 3 or 4
      local cells = size and (axis == "horizontal" and size.columns or size.rows)
      if type(cells) ~= "number" or cells <= 0 or not leaf.rect or not node.rect or node.rect[dimension] <= 0 then
        return false
      end
      local before = layout.first_block(node.split.before)
      local after = layout.first_block(node.split.after)
      if not before or not after then
        return false
      end
      -- Translate terminal cells into Rex's normalized split ratio. Pixel gutters
      -- and integer grid rounding can make the displayed delta differ slightly.
      local delta = amount / cells * leaf.rect[dimension] / node.rect[dimension]
      local sign = (direction == "left" or direction == "up") and -1 or 1
      local ratio = math.max(0.01, math.min(0.99, node.split.ratio + sign * delta))
      if ratio == node.split.ratio then
        return false
      end
      local result = api("session.resize_pane", {
        before_block_id = before,
        after_block_id = after,
        direction = axis,
        ratio = ratio,
      }, options)
      return result ~= nil and type(result.revision) == "number" and result.revision > view.revision
    end
  end
  return false
end

return M
