# smart-splits-backend-rex

A Rex backend for smart-splits.nvim v3 (backend protocol 3.0.0). See `README.md` for what it does and how users set it up.

## Layout

- `lua/smart-splits-backend-rex/init.lua`: the protocol surface: `name`, `protocol_version`, `setup`, `detect`, `move`, `resize`, `health`, plus the non-protocol `cycle`.
- `lua/smart-splits-backend-rex/rex.lua`: everything that talks to Rex, through `rex --autostart=false --timeout … api call -s $REX_SESSION …` via `vim.system`.
- `lua/smart-splits-backend-rex/layout.lua`: pure helpers over `session.view` layout trees.
- `tests/backend.lua`: mocks `vim.system`, so it needs no Rex server, and runs smart-splits' protocol suite when `SMART_SPLITS_PATH` or an installed smart-splits.nvim is available. `tests/live.lua` with `tests/test_live.py` is the opt-in test against a running Rex server.

## Behaviour to keep

- Protocol functions return `false` on every failure, never error, and never start a Rex server. `detect()` must not spawn processes.
- Every Rex call is scoped to `$REX_SESSION`, bounded by `timeout_ms`, and acts only when Rex's active window focuses this Neovim's `$REX_BLOCK`.
- A move counts as done only if the session revision moved on and focus actually left this pane.
- Supports Neovim 0.11 and newer, the same as smart-splits v3.
- The Rex half of the setup (key bindings in Rex's config) is documented in the README; keep that example working with the current Rex Lua API.

## Checks

```sh
nvim --headless -u NONE -l tests/backend.lua
stylua --check lua tests
python3 -m unittest tests.test_release -v
RUN_REX_LIVE_TESTS=1 python3 -m unittest tests.test_live -v   # needs a running Rex server; never touches the user's sessions
```

## Commits and releases

- Use Conventional Commits: `<type>(<scope>): <description>` with `feat`, `fix`, `refactor`, `docs`, `test`, `chore` or `ci`.
- Each push to `main` runs CI; when it passes, `feat`, `fix` and breaking commits since the last tag produce a new tag and GitHub release (`.github/scripts/next-version.sh`). Before 1.0, breaking changes bump the minor version.
- Use generic names and fixtures in tests and docs; never reference real projects, hosts or people.
