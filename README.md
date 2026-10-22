# smart-splits-backend-rex

[![CI](https://github.com/sfrieds3/smart-splits-backend-rex/actions/workflows/ci.yml/badge.svg)](https://github.com/sfrieds3/smart-splits-backend-rex/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sfrieds3/smart-splits-backend-rex?sort=semver)](https://github.com/sfrieds3/smart-splits-backend-rex/releases)

A [Rex](https://www.superlogical.com/rex) backend for [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) v3.

Move and resize across the Neovim/Rex boundary with one set of keys. `<C-h/j/k/l>` walks Neovim's windows until it runs out of them, then keeps walking Rex's panes. Resizing works the same way. At the outer edge, movement can stop, wrap around, or open a new Rex pane.

smart-splits v3 moved every multiplexer out into its own plugin, built against its [backend protocol](https://github.com/mrjones2014/smart-splits.nvim/blob/master/PROTOCOL.md). This is that plugin for Rex, implementing protocol 3.0.0. It's modelled on the official [tmux backend](https://github.com/smart-splits-nvim/backend-tmux).

## Requirements

- Neovim 0.11 or newer and smart-splits.nvim v3
- Rex, with `rex` on Neovim's `PATH`. Rex sets `REX_SESSION` and `REX_BLOCK` in the panes it starts, and adds `rex` to their `PATH`.

## Install

Two halves have to agree: this plugin, which handles the keys while Neovim has them, and a few Rex key bindings, which handle them everywhere else.

### Neovim

With `vim.pack` (Neovim 0.12):

```lua
vim.pack.add({
  "https://github.com/mrjones2014/smart-splits.nvim",
  "https://github.com/sfrieds3/smart-splits-backend-rex",
})

require("smart-splits").setup({
  mux = { backend = "smart-splits-backend-rex" },
})

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  vim.keymap.set("n", "<C-" .. key .. ">", require("smart-splits")["move_cursor_" .. direction])
  vim.keymap.set("n", "<M-" .. key .. ">", require("smart-splits")["resize_" .. direction])
end
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "mrjones2014/smart-splits.nvim",
  opts = { mux = { backend = "smart-splits-backend-rex" } },
  dependencies = { "sfrieds3/smart-splits-backend-rex" },
}
```

Backends are tried in order, so one config can travel between terminals. Put tmux first, so that Neovim inside tmux inside Rex moves between tmux panes:

```lua
mux = { backend = { "smart-splits-backend-tmux", "smart-splits-backend-rex" } },
```

### Rex

Bind the same keys in `~/.config/rex/init.lua`. When Neovim is in the focused pane, the binding hands the key to it, and smart-splits takes over; anywhere else, Rex moves between its own panes:

```lua
local editors = { nvim = true, vim = true }

local function in_editor(ctx)
  local process = rex.call("com.superlogical.terminal.process", {
    session_id = ctx.session_id,
    block_id = ctx.block_id,
    args = {},
  })
  local foreground = process and process.foreground
  local name = type(foreground) == "table" and type(foreground.name) == "string" and foreground.name
  return name and editors[name:match("[^/]+$")] or false
end

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+" .. key, function(ctx)
    if not ctx.block_id or in_editor(ctx) then
      return false -- unhandled: the key goes to the pane
    end
    return rex.call("session.focus_direction", {
      session_id = ctx.session_id,
      direction = direction,
      wrap = true,
    }) ~= nil
  end)
end
```

Returning `false` leaves a key unhandled, so it reaches the program in the pane. A fuller version can:
- check the process's ancestors as well as the foreground process,
- pass keys to tmux, SSH and mosh too,
- resize with `session.resize_pane`, the same way the backend does,
- bind a second set of keys that writes the Neovim key sequences into the pane (`com.superlogical.terminal.write`), for terminals where those chords are taken.

## Behaviour

- **Moving:** Neovim moves between its own windows first and calls Rex only at an edge. All three `at_edge` behaviours work: `stop` stays put, `wrap` wraps around the Rex window, and `split` opens a new shell pane on that side and focuses it.
- **Resizing:** smart-splits' resize amount is in terminal cells. The backend turns it into a change of Rex's split ratio, using the pane's grid size. Gutters and rounding can make the visible change differ by a cell. Zoomed panes aren't resized.
- **Swapping buffers:** this stays inside Neovim, because the protocol has no hook for swapping panes.
- **Only its own pane:** the backend acts only when Rex's active window has this Neovim's pane focused. A command from an older Neovim instance can't move focus somewhere else.
- **Never stalls:** the backend never starts a Rex server. Each `rex` call is bounded by `timeout_ms`, and any failure returns `false`, so smart-splits falls back to plain window movement.
- **Detection:** `detect()` checks for `REX_SESSION`, `REX_BLOCK` and `rex` on `PATH` without running anything. `:checkhealth smart-splits` reports the result.

### Cycling

smart-splits has no protocol call for cycling, so the backend adds its own. `cycle("next")` and `cycle("previous")` move through Neovim's windows in the current tab. After the last window they hand off to Rex's next or previous pane. They wrap within Neovim when there's no other Rex pane, or inside tmux.

```lua
vim.keymap.set("n", "<M-]>", function() require("smart-splits-backend-rex").cycle("next") end)
vim.keymap.set("n", "<M-[>", function() require("smart-splits-backend-rex").cycle("previous") end)
```

## Options

Call `setup` before smart-splits' own setup, if at all:

```lua
require("smart-splits-backend-rex").setup({
  enable = true,    -- false turns the backend off; detect() returns false
  timeout_ms = 500, -- limit for each rex call
})
```

## Troubleshooting

- **The keys never leave Neovim.** Check `:checkhealth smart-splits`: Neovim needs `REX_SESSION`, `REX_BLOCK` and `rex` on its `PATH`. Inside tmux, the tmux backend wins if it's listed first.
- **The keys never reach Neovim.** The Rex binding is handling them. Check that its editor test matches how Neovim shows up in the pane's process list (`rex block call process`).
- **Over SSH.** A remote Neovim has no local Rex. Pass the keys through to SSH in the Rex binding, and use the remote side's own multiplexer.

## Development

```sh
nvim --headless -u NONE -l tests/backend.lua                     # mocked Rex calls, no server needed
RUN_REX_LIVE_TESTS=1 python3 -m unittest tests.test_live -v      # against a running Rex server
stylua --check lua tests
python3 -m unittest tests.test_release -v                        # the release workflow's version bump
```

`tests/backend.lua` also runs smart-splits' protocol conformance suite, and checks how backends are chosen, whenever smart-splits.nvim is installed or `SMART_SPLITS_PATH` points to it. CI pins a smart-splits commit and runs the suite on Neovim 0.11, stable and nightly. The live test creates its own detached Rex session, runs real moves, resizes and splits in it, and deletes it afterwards.

Each push to `main` with a `feat`, `fix` or breaking commit is tagged and released, following [Conventional Commits](https://www.conventionalcommits.org). Before 1.0, a breaking change bumps the minor version.

## Credits

The protocol and module layout follow [smart-splits-nvim/backend-template](https://github.com/smart-splits-nvim/backend-template). smart-splits.nvim is by Mat Jones.

## License

[MIT](LICENSE)
