-- Only run through tests/test_live.py, which owns an isolated session.
assert(vim.env.REX_TEST_SESSION == vim.env.REX_SESSION, "isolated Rex test session required")
vim.opt.rtp:prepend(vim.fn.getcwd())
local backend = require("smart-splits-backend-rex")
local function api(method, args)
  local result = vim
    .system({
      "rex",
      "--autostart=false",
      "api",
      "call",
      "-s",
      vim.env.REX_SESSION,
      method,
      vim.json.encode(args or vim.empty_dict()),
    }, { text = true })
    :wait(2000)
  assert(result.code == 0, result.stderr)
  return vim.json.decode(result.stdout)
end
local function window()
  return api("session.view").windows[1]
end
assert(backend.detect())
local a = vim.env.REX_BLOCK
local split = api("session.new_split", {
  anchor_block_id = a,
  direction = "horizontal",
  side = "after",
  focus = false,
  layout = { block = { flavor = "com.superlogical.terminal.shell" } },
})
local b = split.block_ids[1]
assert(backend.move("right", { at_edge = "stop" }))
assert(window().focused_block_id == b)
vim.env.REX_BLOCK = b
assert(not backend.move("right", { at_edge = "stop" }))
assert(backend.move("right", { at_edge = "wrap" }))
assert(window().focused_block_id == a)
vim.env.REX_BLOCK = a
local before = window().layers[1].layout.split.ratio
assert(backend.resize("left", { amount = 3 }))
assert(window().layers[1].layout.split.ratio < before)
assert(window().focused_block_id == a, "resize must preserve focus")
assert(backend.move("right", { at_edge = "stop" }))
vim.env.REX_BLOCK = b
before = window().layers[1].layout.split.ratio
assert(backend.resize("right", { amount = 3 }))
assert(window().layers[1].layout.split.ratio > before)
assert(backend.move("down", { at_edge = "split" }))
local c = window().focused_block_id
assert(c ~= a and c ~= b)
vim.env.REX_BLOCK = c
assert(backend.resize("up", { amount = 2 }))
assert(backend.move("up", { at_edge = "stop" }))
assert(window().focused_block_id == b)
print("Live Rex backend checks passed")
