# AGENTS.md

This file is for coding agents working in `swine.nvim`.
It explains the plugin architecture, where behavior lives, and how tests run.

## Quick map

- `lua/swine/init.lua`: plugin entrypoint, orchestration, commands, extmarks,
  async process handling, and highlight setup.
- `lua/swine/backend/init.lua`: backend registry and backend option resolver.
- `lua/swine/backend/swi.lua`: SWI-Prolog backend.
- `lua/swine/backend/scryer.lua`: Scryer backend PoC.
- `lua/swine/query_markers.lua`: parses `%?`, `%??`, `%N?`, and `%|`
  continuation blocks.
- `lua/swine/diag_parser.lua`: parses SWI-like load diagnostics into Neovim
  diagnostics.
- `lua/swine/query_output.lua`: parses query process output into
  renderable rows.
- `tests/`: custom headless test harness plus unit and integration specs.
- `doc/swine.txt`: `:help` docs.

## Runtime architecture

### High-level flow

`SwineRun` (or `swine.run(buf)`) does this:

1. Validate buffer and selected backend availability.
2. Spawn backend load command for the file.
3. Parse load stderr/stdout with backend `parse_load_diags`.
4. Render diagnostics and diagnostic virtual lines.
5. If load has errors, timeout, or non-zero code, stop and show status.
6. Otherwise parse query markers from buffer lines.
7. Spawn one backend query process per query marker.
8. Parse each query output with backend `parse_query_output`.
9. Render query result virtual lines under each query anchor line.

### Backends

Backends are resolved in `setup({ backend = ... })`.

- Builtin string ids: `"swi"` (default), `"scryer"`.
- Alias: `"swipl"` resolves to `"swi"`.
- You can pass a backend table implementing:
  - `id`, `label`
  - `build_load_cmd(file)`
  - `build_query_cmd(file, query, max_solutions)`
  - `parse_load_diags(file, text)`
  - `parse_query_output(text, obj, timeout_ms)`
  - `is_timeout_result(obj, text)`
  - `is_available()`
  - `missing_message()`

The registry provides defaults for some optional helpers if omitted.

### Namespaces and state

`init.lua` creates three namespaces:

- `swine_diag`: Neovim diagnostics namespace.
- `swine_virt`: virtual lines for load diagnostics.
- `swine_qres`: status extmark plus query result virtual lines.

Per-buffer state is stored in a local `state[buf]` table with:

- `seq`: run sequence number used for stale async result rejection.
- `status_mark`: extmark id for top-of-buffer status `virt_text`.
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
- Result extmarks render under the final line in the block.
- When there is a following buffer line, marks are anchored above that next
  line so virtual cells move up/down like normal lines on surrounding edits.
- At EOF, marks fall back to the final query line end column anchor.

### Diagnostics parsing

`diag_parser.lua` currently parses SWI-like formats:

- `ERROR: file:line:col: message`
- `ERROR: file:line: message`
- `Warning: file:line: message`
- file filtering to active file
- optional SWI thread prefixes like `[Thread main]`

Returned diagnostics are 0-based (`lnum`, `col`) for Neovim.

### Query output parsing

Implemented in `query_output.lua`.

Backends are expected to print machine-readable markers:

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
- `tests/unit/backend_spec.lua`: backend resolution and backend option wiring.

### Integration tests

`tests/integration/run_spec.lua` covers end-to-end plugin behavior for SWI:

- diagnostics appear after load errors
- query result virtual lines are rendered
- multiline `%|` markers render query results from the final marker line
- query result extmarks move correctly when nearby lines are edited
- status text is rendered via `virt_text` on the first buffer line
- stale async runs do not overwrite newer run results

`tests/integration/scryer_spec.lua` covers Scryer backend behavior:

- diagnostics appear for syntax errors
- diagnostics appear for singleton variable warnings
- query result virtual lines are rendered
- unsatisfied queries render `false`

Integration tests skip if required backend executables are missing from `PATH`.

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
`neovim`, `swi-prolog`, and `scryer-prolog` provided.

## Agent notes

- Prefer editing `lua/swine/*.lua`; behavior is still centralized in
  `init.lua`, with backend logic in `lua/swine/backend/*`.
- Keep async race safety intact (`seq` checks in callbacks).
- If you change marker grammar or output markers, update:
  - backend output generation/parsing
  - parser module
  - rendering behavior if needed
  - unit tests
  - integration tests
  - docs (`README.md` and `doc/swine.txt`)
- Validate with the headless test command before handing off changes.
