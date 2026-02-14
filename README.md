

https://github.com/user-attachments/assets/dcf42c46-2d15-490f-9dd5-b3cf14d9a58e

# swine.nvim

SWI Notebook Environment for Neovim.

`swine.nvim` gives a notebook-style workflow for Prolog files:

- loads `.pl` files with `swipl`
- shows load errors as diagnostics
- runs inline query comments
- renders results as virtual lines under query lines

## Install

Use your plugin manager and call setup:

```lua
require("swine").setup({
  pattern = "*.pl",
  run_on_save = false,
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

## Query markers

Use comment markers so source remains valid Prolog:

- `%? goal.` → 1 solution
- `%?? goal.` → 2 solutions
- `%??? goal.` → 3 solutions
- `%N? goal.` → N solutions (example `%5? member(X, [a,b,c,d,e]).`)

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
