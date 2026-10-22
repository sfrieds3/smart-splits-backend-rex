-- Run from the repository root: nvim --headless -u NONE -l tests/backend.lua
-- Fully isolated: no real Rex command may run in these tests.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local original_system = vim.system
local original_executable = vim.fn.executable
local queue, calls = {}, {}
vim.env.REX_SESSION, vim.env.REX_BLOCK = "session:test", "block:a"
vim.fn.executable = function(name)
  return name == "rex" and 1 or original_executable(name)
end
vim.system = function(argv)
  calls[#calls + 1] = argv
  assert(argv[1] == "rex" and argv[2] == "--autostart=false")
  assert(argv[3] == "--timeout" and argv[4] == "500ms")
  local response = table.remove(queue, 1)
  assert(response, "unexpected Rex call: " .. table.concat(argv, " "))
  if response.spawn_error then
    error("cannot spawn rex")
  end
  return {
    wait = function(_, timeout)
      assert(timeout == 500)
      return { code = response.code or 0, stdout = response.raw or vim.json.encode(response) }
    end,
  }
end

local backend = require("smart-splits-backend-rex")
local function view(axis, focus, block)
  axis = axis or "horizontal"
  local horizontal = axis == "horizontal"
  local a = { block_id = "block:a", rect = horizontal and { 0, 0, 0.5, 1 } or { 0, 0, 1, 0.5 } }
  local b = { block_id = "block:b", rect = horizontal and { 0.5, 0, 0.5, 1 } or { 0, 0.5, 1, 0.5 } }
  return {
    revision = 10,
    active_window_id = "window:test",
    windows = {
      {
        window_id = "window:test",
        focused_block_id = focus or block or "block:a",
        layers = {
          {
            layout = {
              rect = { 0, 0, 1, 1 },
              split = {
                direction = axis,
                ratio = 0.5,
                before = a,
                after = b,
              },
            },
          },
        },
      },
    },
  }
end
local function reset(responses)
  queue, calls = responses or {}, {}
  vim.env.REX_BLOCK = "block:a"
  backend.setup()
end
local function args()
  return vim.json.decode(calls[#calls][#calls[#calls]])
end

assert(backend.detect())
assert(#calls == 0, "detect must not spawn processes")
backend.setup({ enable = false })
assert(not backend.detect())
backend.setup()
vim.env.REX_BLOCK = nil
assert(not backend.detect())
vim.env.REX_BLOCK = "block:a"
vim.fn.executable = function()
  return 0
end
assert(not backend.detect())
vim.fn.executable = function()
  return 1
end

for _, direction in ipairs({ "left", "right", "up", "down" }) do
  for _, edge in ipairs({ "stop", "wrap" }) do
    local after = view(nil, "block:b")
    after.revision = 11
    reset({ view(), { revision = 11 }, after })
    assert(backend.move(direction, { at_edge = edge, unknown = true }))
    local request = vim.json.decode(calls[2][#calls[2]])
    assert(request.direction == direction and request.wrap == (edge == "wrap"))
    assert(calls[2][8] == "session:test", "explicit session target required")
    assert(#queue == 0)
  end
  reset({ view(), { revision = 10 } })
  assert(not backend.move(direction), "edge no-op must return false")
  reset({ view(), { revision = 10 }, { block_ids = { "block:new" }, revision = 11 } })
  assert(backend.move(direction, { at_edge = "split" }))
  assert(args().anchor_block_id == "block:a" and args().focus)
  assert(args().side == ((direction == "left" or direction == "up") and "before" or "after"))
  assert(args().direction == ((direction == "left" or direction == "right") and "horizontal" or "vertical"))
end

for _, field in ipairs({ "windows", "layers" }) do
  local empty = view()
  if field == "windows" then
    empty.windows = vim.NIL
  else
    empty.windows[1].layers = vim.NIL
  end
  reset({ empty })
  assert(not backend.move("left"), "nullable " .. field .. " must return false")
  reset({ empty })
  assert(not backend.resize("left"))
end
reset({ view(), { revision = 11 }, { revision = 11, windows = vim.NIL } })
assert(not backend.move("right"), "concurrent closure must return false")
reset({ view(), { revision = 11 }, view() })
assert(not backend.move("right"), "unrelated revision change isn't movement")
reset({ view(nil, "block:b") })
assert(not backend.move("right") and #calls == 1, "must not move someone else's focus")
local inactive = view()
inactive.active_window_id = "window:other"
reset({ inactive })
assert(not backend.move("right") and #calls == 1)

for _, failure in ipairs({
  { code = 1 },
  { code = 124 },
  { raw = "not json" },
  { raw = "null" },
  { spawn_error = true },
}) do
  reset({ failure })
  assert(not backend.move("left"))
  reset({ failure })
  assert(not backend.resize("left"))
end

for _, axis in ipairs({ "horizontal", "vertical" }) do
  for _, block in ipairs({ "block:a", "block:b" }) do
    local directions = axis == "horizontal" and { "left", "right" } or { "up", "down" }
    for i, direction in ipairs(directions) do
      reset({ view(axis, block), { columns = 50, rows = 50 }, { revision = 11 } })
      vim.env.REX_BLOCK = block
      assert(backend.resize(direction, { amount = 10 }))
      local request = args()
      assert(request.direction == axis)
      assert(math.abs(request.ratio - (i == 1 and 0.4 or 0.6)) < 1e-9, "cell count/sign mismatch")
      assert(request.before_block_id == "block:a" and request.after_block_id == "block:b")
      assert(calls[2][10] == block, "size query must target Neovim's pane")
      assert(#queue == 0)
    end
  end
end
reset({ view("vertical") })
assert(not backend.resize("left"), "no matching border")
reset({ view(), { columns = 0, rows = 0 } })
assert(not backend.resize("left"))
reset({ view(), { columns = 50 }, { revision = 10 } })
assert(not backend.resize("left"), "resize no-op")
for _, direction in ipairs({ "next", "previous" }) do
  local after = view(nil, "block:b")
  after.revision = 11
  reset({ view(), { revision = 11 }, after })
  backend.cycle(direction)
  assert(calls[2][#calls[2] - 1] == "session.focus_" .. direction .. "_pane")
  assert(vim.json.decode(calls[2][#calls[2]]).wrap)
  assert(#queue == 0)
end
vim.cmd("vsplit | wincmd h")
local first = vim.api.nvim_get_current_win()
reset()
backend.cycle("next")
local last = vim.api.nvim_get_current_win()
assert(last ~= first and #calls == 0, "internal cycling must not invoke Rex")
reset({ view(), { revision = 10 } })
backend.cycle("next")
assert(vim.api.nvim_get_current_win() == first and #queue == 0, "single Rex pane wraps in Neovim")
vim.env.TMUX = "test"
reset()
backend.cycle("previous")
assert(vim.api.nvim_get_current_win() == last and #calls == 0, "tmux must not cycle Rex panes")
vim.env.TMUX = nil
vim.cmd("only")

reset()
assert(not backend.resize("left", { amount = -1 }))
assert(not backend.move("invalid"))

-- smart-splits' protocol suite and backend resolution, when smart-splits.nvim is available: from
-- SMART_SPLITS_PATH (CI checks out a pinned copy) or an installed package.
local packages = (vim.env.SMART_SPLITS_PATH or "") ~= "" and { vim.env.SMART_SPLITS_PATH }
  or vim.fn.glob(vim.fn.stdpath("data") .. "/site/pack/*/*/smart-splits.nvim", false, true)
if vim.env.REQUIRE_SMART_SPLITS == "1" then
  assert(#packages > 0 and vim.uv.fs_stat(packages[1] .. "/lua/smart-splits"), "smart-splits.nvim not found")
end
if #packages > 0 then
  vim.opt.rtp:append(packages[1])
  -- No Rex environment means the conformance suite exercises safe false returns.
  vim.env.REX_BLOCK = nil
  for _, result in ipairs(require("smart-splits.protocol_tests").run(backend)) do
    assert(result.ok == true, result.name .. ": " .. tostring(result.ok))
  end
  package.loaded["smart-splits-backend-tmux"] = {
    name = "tmux",
    protocol_version = "3.0.0",
    detect = function()
      return vim.env.TMUX == "test"
    end,
    move = function()
      return false
    end,
  }
  local splits = require("smart-splits")
  local resolver = require("smart-splits.backend")
  splits.setup({ mux = { backend = { "smart-splits-backend-tmux", "smart-splits-backend-rex" } } })
  vim.env.REX_BLOCK, vim.env.TMUX = "block:a", "test"
  resolver.reset()
  assert(resolver.resolve().name == "tmux", "nested tmux must win")
  vim.env.TMUX = nil
  resolver.reset()
  assert(resolver.resolve().name == "rex")
  reset()
  vim.cmd("vsplit | wincmd h")
  local left = vim.api.nvim_get_current_win()
  vim.cmd("wincmd l")
  splits.move_cursor_left()
  assert(vim.api.nvim_get_current_win() == left and #calls == 0, "internal navigation must not invoke Rex")
  splits.resize_left(2)
  assert(#calls == 0, "internal resizing must not invoke Rex")
  vim.env.REX_BLOCK = nil
  resolver.reset()
  assert(resolver.resolve() == nil, "ordinary Neovim must not select Rex")
end
vim.system, vim.fn.executable = original_system, original_executable
print(#packages > 0 and "Rex backend checks passed (with smart-splits protocol suite)" or "Rex backend checks passed")
