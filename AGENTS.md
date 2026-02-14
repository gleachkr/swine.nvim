# AGENTS.md

This file is for coding agents working in `swine.nvim`.
It explains the plugin architecture, where behavior lives, and how tests run.

## Quick map

- `lua/swine/init.lua`: plugin entrypoint, orchestration, commands, extmarks,
  async process handling, and highlight setup.
- `lua/swine/query_markers.lua`: parses `%?`, `%??`, `%N?`, and `%|`
  continuation blocks.
- `lua/swine/diag_parser.lua`: parses SWI-Prolog load diagnostics into Neovim
  diagnostics.
- `lua/swine/query_output.lua`: parses query process output into
  renderable rows.
- `tests/`: custom headless test harness plus unit and integration specs.
- `doc/swine.txt`: `:help` docs.

## Runtime architecture

### High-level flow

`SwineRun` (or `swine.run(buf)`) does this:

1. Validate buffer and `swipl` availability.
2. Spawn `swipl` to load the file (`-l <file> -g halt`).
3. Parse load stderr/stdout with `diag_parser.parse`.
4. Render diagnostics and diagnostic virtual lines.
5. If load has errors or timed out, stop and show status.
6. Otherwise parse query markers from buffer lines.
7. Spawn one `swipl` process per query marker.
8. Parse each query output with `query_output.parse`.
9. Render query result virtual lines under each query anchor line.

### Namespaces and state

`init.lua` creates three namespaces:

- `swine_diag`: Neovim diagnostics namespace.
- `swine_virt`: virtual lines for load diagnostics.
- `swine_qres`: status and query result virtual lines.

Per-buffer state is stored in a local `state[buf]` table with:

- `seq`: run sequence number used for stale async result rejection.
- `status_mark`: extmark id for the top status line.
- `diag_marks`: extmark ids keyed by diagnostic identity.
- `query_marks`: extmark ids keyed by anchor line number.

The `seq` guard is important: each run increments `seq`, and async callbacks
ignore results from older runs.

### Query marker semantics

Implemented in `query_markers.lua`:

- `%? goal.` -> max 1 solution
- `%?? goal.` -> max 2 solutions (or count of question marks)
- `%N? goal.` -> max N solutions
- `%| ...` -> continuation line for the most recent query marker

Collection behavior:

- Query text can span multiple lines via `%|` lines.
- Blank `%|` lines are preserved as blank lines in the assembled query.
- A block ends at the first non-`%|` line.
- Trailing `.` is stripped from the assembled query.
- Result extmarks are anchored to the final line in the block, at line end.

### Diagnostics parsing

Implemented in `diag_parser.lua`:

- Parses `ERROR: file:line:col: message`
- Parses `ERROR: file:line: message`
- Parses `Warning: file:line: message`
- Filters to the active file only.
- Handles SWI thread prefixes like `[Thread main]`.

Returned diagnostics are 0-based (`lnum`, `col`) for Neovim.

### Query output parsing

Implemented in `query_output.lua`.

`init.lua` runs queries using a generated SWI goal that prints
machine-readable markers:

- `PLNB_SOL <idx> <payload>`
- `PLNB_FALSE`
- `PLNB_ERROR <term>`

`query_output.parse` maps these to rows of `{ text, kind }` where `kind` is
`hint`, `warn`, or `error`, then the renderer applies highlight groups.

### Rendering and highlights

`init.lua` renders virtual lines with:

- optional left bar (`virt_lines_bar`, default `▌`)
- optional right padding (`virt_lines_pad`) so background extends uniformly
- per-severity highlight resolution (`error`, `warn`, `hint`, `info`)

Highlight flow:

- default diagnostic virtual text groups are used when no override is set
- `virt_lines_hl` can link to one group (`string`) or per kind (`table`)
- `virt_lines_bg = "auto"` derives a subtle bg from `Normal`-family groups
- custom groups `SwineVirtError/Warn/Hint/Info` are regenerated on
  `ColorScheme`

### Commands and autocmds

Defined in `setup()`:

- `:SwineRun [bufnr]`
- `:SwineClear [bufnr]`
- `:SwineToggleAuto`

If `run_on_save = true`, a `BufWritePost` autocmd (matching `pattern`) calls
`run_for_buf`.

## Test infrastructure

There is a custom Lua test harness, not busted/plenary test runner.

### Test bootstrap

- `tests/minimal_init.lua` sets runtime path to repo root and adjusts
  `package.path`.
- If `PLENARY_PATH` is set, it appends that runtime path, but the current
  tests do not require plenary APIs.

### Test runner

`tests/run_unit.lua` is the single entrypoint.

It:

- requires each spec module listed in `modules`
- executes each exported test case with shared helpers
- prints pass/fail/skip lines
- exits headless Neovim with `cquit 1` on failures

### Test helpers

`tests/unit/helpers.lua` provides:

- assertions (`eq`, `ok`, `is_nil`, `contains`)
- skipping (`skip`) via a known prefix consumed by the runner
- async polling (`wait_for`) built on `vim.wait`
- temp file and buffer helpers
- extmark inspection helpers for virtual line checks

### Unit tests

- `tests/unit/query_markers_spec.lua`: marker parse and multiline collection.
- `tests/unit/diag_parser_spec.lua`: load error/warning parsing and filtering.
- `tests/unit/query_output_spec.lua`: machine-marker output parsing behavior.

### Integration tests

`tests/integration/run_spec.lua` covers end-to-end plugin behavior:

- diagnostics appear after load errors
- query result virtual lines are rendered
- multiline `%|` markers anchor extmarks on final line end column
- extmarks move correctly when the anchor line is edited
- stale async runs do not overwrite newer run results

Integration tests require `swipl` in `PATH`. If missing, tests skip.

### Running tests

From repo root:

```sh
nvim --headless -u tests/minimal_init.lua -i NONE \
  -c "lua dofile('tests/run_unit.lua')"
```

With Nix:

```sh
nix flake check
```

`flake.nix` defines `checks.tests` that runs the same headless command with
`neovim` and `swi-prolog` provided.

## Agent notes

- Prefer editing `lua/swine/*.lua`; behavior is mostly centralized in
  `init.lua`.
- Keep async race safety intact (`seq` checks in callbacks).
- If you change marker grammar or output markers, update:
  - parser module
  - rendering behavior if needed
  - unit tests
  - integration tests
  - docs (`README.md` and `doc/swine.txt`)
- Validate with the headless test command before handing off changes.
