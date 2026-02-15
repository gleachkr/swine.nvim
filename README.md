

https://github.com/user-attachments/assets/dcf42c46-2d15-490f-9dd5-b3cf14d9a58e

# swine.nvim

SWI Notebook Environment for Neovim. Supports other Prologs too.

`swine.nvim` gives a notebook-style loop for `.pl` files:

- loads files with a selectable Prolog backend
- shows load errors as diagnostics
- runs inline query comments
- renders results as virtual lines under query lines

## Install

Use your plugin manager and call setup:

```lua
require("swine").setup({
  pattern = "*.pl",
  run_on_save = false,
  backend = "swi", -- "swi" (default), "swipl" alias, or "scryer"
  max_solutions = 50,
  load_timeout_ms = 4000,
  query_timeout_ms = 4000,
  virt_lines_bg = "auto",
  virt_lines_hl = nil,
  virt_lines_overflow = "scroll",
  virt_lines_leftcol = true,
  virt_lines_bar = "▌",
  virt_lines_pad = true,
  virt_lines_pad_extra = 1,
})
```

`virt_lines_bg = "auto"` is the default. It derives a subtle background from
`Normal` so virtual lines stay visible without being loud.

By default, swine pads each virtual line with trailing spaces so the
background extends beyond the rendered text. For multi-line result blocks,
padding is aligned to the longest rendered line, then adds
`virt_lines_pad_extra`.

## Backend support

Builtin backend ids:

- `"swi"` (default)
- `"swipl"` (alias for `"swi"`)
- `"scryer"` (experimental PoC)

You can also pass a custom backend table:

```lua
require("swine").setup({
  backend = {
    id = "myprolog",
    label = "My Prolog",
    executable = "my-prolog",
    build_load_cmd = function(file)
      return { "my-prolog", file, "-g", "halt" }
    end,
    build_query_cmd = function(file, query, max_solutions)
      return { "my-prolog", file, "-g", query }
    end,
  },
})
```

For custom backends, optional parser hooks fall back to the default
`query_output` parser where possible.

## Query markers

Use comment markers so source remains valid Prolog:

- `%? goal.` → 1 solution
- `%?? goal.` → 2 solutions
- `%??? goal.` → 3 solutions
- `%N? goal.` → N solutions (example `%5? member(X, [a,b,c,d,e]).`)
- `%| ...` → continuation line for the most recent `%?`/`%??`/`%N?` marker

Continuation lines let you write multi-line queries:

```prolog
%? member(X, [a,b,c]),
%| X \= b,
%| writeln(X).
```

Blank continuation lines are allowed:

```prolog
%? member(X, [a,b,c]),
%|
%| X \= b.
```

A continuation block ends at the first non-`%|` line.
Results render under the final line of the block.
When there is a following buffer line, swine anchors virtual lines above that
next line so query cells move like normal lines when editing nearby text.
At EOF, anchoring falls back to the final query line end column.

## Commands

- `:SwineRun` or `:SwineRun {bufnr}`
- `:SwineClear` or `:SwineClear {bufnr}`
- `:SwineToggleAuto`

## Highlight customization

You can customize virtual-line highlights two ways:

1. Set only background:

```lua
require("swine").setup({
  virt_lines_bg = "#1f2335",
})
```

2. Link to existing groups globally or per severity:

```lua
require("swine").setup({
  virt_lines_hl = "Comment", -- all swine virtual lines
})

require("swine").setup({
  virt_lines_hl = {
    all = "Comment",
    error = "DiagnosticVirtualTextError",
    warn = "DiagnosticVirtualTextWarn",
    hint = "DiagnosticVirtualTextHint",
  },
})
```

If both `virt_lines_hl` and `virt_lines_bg` are set, swine keeps the linked
style/fg and overrides only background.

Virtual-line rendering controls:

```lua
require("swine").setup({
  virt_lines_overflow = "scroll", -- or "trunc"
  virt_lines_leftcol = true,       -- draw over sign/number columns
  virt_lines_bar = "▌",           -- left marker ("" to disable)
  virt_lines_pad = true,           -- trailing-space padding hack
  virt_lines_pad_extra = 1,        -- appended after alignment width
})
```

## Help docs

This repo includes `:help` docs in `doc/swine.txt`.

If your plugin manager does not run `:helptags` automatically, run:

```vim
:helptags {path-to-repo}/doc
```

Then use:

```vim
:help swine.nvim
```

## Development / tests

Run parser unit tests in headless Neovim:

```sh
nvim --headless -u tests/minimal_init.lua -i NONE \
  -c "lua dofile('tests/run_unit.lua')"
```

With Nix:

```sh
nix flake check
```
