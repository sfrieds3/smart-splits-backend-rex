-- The Rex half, with a stubbed rex API. Run from the repository root with lua5.1, luajit or nvim -l:
-- lua tests/rex.lua
local requests, process, fail = {}, { foreground = { name = "zsh" } }, false
local view = {
  revision = 1,
  active_window_id = "window:test",
  windows = {
    {
      window_id = "window:test",
      focused_block_id = "block:test",
      layers = {
        {
          layout = {
            rect = { 0, 0, 1, 1 },
            split = {
              direction = "horizontal",
              ratio = 0.5,
              before = { block_id = "block:test", rect = { 0, 0, 0.5, 1 } },
              after = { block_id = "block:other", rect = { 0.5, 0, 0.5, 1 } },
            },
          },
        },
      },
    },
  },
}
rex = {
  call = function(method, args)
    requests[#requests + 1] = { method = method, args = args }
    if fail then
      return nil, "unavailable"
    end
    if method == "com.superlogical.terminal.process" then
      return process
    end
    if method == "com.superlogical.terminal.size" then
      return { columns = 50, rows = 50 }
    end
    if method == "session.view" then
      return view
    end
    return { revision = 2, bytes_written = args.args and #(args.args.data or "") or 0 }
  end,
}
-- dofile, not require: under nvim -l, require would find the Neovim module of the same name.
local splits = dofile("rex/smart-splits-backend-rex.lua")
local ctx = { session_id = "session:test", block_id = "block:test" }
local function last()
  return requests[#requests]
end

-- At a shell, Rex moves, cycles and resizes its own panes.
for _, direction in ipairs({ "left", "down", "up", "right" }) do
  for _, alias in ipairs({ false, true }) do
    requests = {}
    assert(splits.focus(direction, alias)(ctx))
    assert(requests[1].method == "com.superlogical.terminal.process" and requests[1].args.block_id == ctx.block_id)
    assert(requests[2].method == "session.focus_direction")
    assert(requests[2].args.session_id == ctx.session_id)
    assert(requests[2].args.direction == direction and requests[2].args.wrap)
  end
end
for _, direction in ipairs({ "previous", "next" }) do
  requests = {}
  assert(splits.cycle(direction, true)(ctx))
  assert(requests[2].method == "session.focus_" .. direction .. "_pane")
  assert(requests[2].args.session_id == ctx.session_id and requests[2].args.wrap)
end
assert(splits.resize("left")(ctx))
assert(last().method == "session.resize_pane")
assert(math.abs(last().args.ratio - 0.47) < 1e-9, "3 of 50 cells in a half-width pane")
assert(last().args.before_block_id == "block:test" and last().args.after_block_id == "block:other")
assert(splits.resize("right", true)(ctx))
assert(math.abs(last().args.ratio - 0.53) < 1e-9)
assert(not splits.resize("down")(ctx), "no vertical border")
view.windows[1].zoomed_block_id = "block:test"
assert(not splits.resize("left")(ctx), "zoomed panes aren't resized")
view.windows[1].zoomed_block_id = nil

-- Programs that own the keys get them: unchanged without an alias, as smart-splits' sequences with one.
for _, name in ipairs({ "nvim", "vim", "tmux", "ssh", "mosh", "mosh-client" }) do
  process = { foreground = { name = name } }
  requests = {}
  assert(not splits.focus("left")(ctx))
  assert(#requests == 1, "must pass the original key through")
  assert(not splits.resize("left")(ctx))
  for handler, data in pairs({
    [splits.focus("left", true)] = "\27[104;7u",
    [splits.focus("right", true)] = "\27[108;7u",
    [splits.resize("left", true)] = "\27[1;2P",
    [splits.resize("down", true)] = "\27[1;2Q",
    [splits.cycle("previous", true)] = "\27[91;3u",
    [splits.cycle("next", true)] = "\27[93;3u",
  }) do
    assert(handler(ctx))
    assert(last().method == "com.superlogical.terminal.write" and last().args.args.data == data)
    assert(last().args.block_id == ctx.block_id)
  end
end
process = { foreground = { path = "/opt/bin/nvim" } }
assert(not splits.focus("left")(ctx), "matches the path's basename")
process = { foreground = { name = "helper" }, ancestors = { { path = "/usr/bin/nvim" } } }
assert(not splits.focus("left")(ctx), "an editor among the ancestors owns the keys")

-- Missing or failing process data never swallows a key.
process = {}
assert(not splits.focus("left")(ctx))
fail = true
assert(not splits.focus("left")(ctx))
fail = false
assert(not splits.focus("left")({}))

-- setup: extra programs and the resize step.
process = { foreground = { name = "helix" } }
assert(splits.focus("left")(ctx), "unknown programs don't get the keys")
splits.setup({ passthrough = { "helix" }, resize_amount = 5 })
assert(not splits.focus("left")(ctx))
process = { foreground = { name = "nvim" } }
assert(not splits.focus("left")(ctx), "defaults stay when adding names")
process = { foreground = { name = "zsh" } }
assert(splits.resize("left")(ctx))
assert(math.abs(last().args.ratio - 0.45) < 1e-9)
splits.setup()
process = { foreground = { name = "helix" } }
assert(splits.focus("left")(ctx), "setup() resets to the defaults")

print("Rex half checks passed")
