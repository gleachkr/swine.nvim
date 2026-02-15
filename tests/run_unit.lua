local helpers = require("tests.unit.helpers")

local modules = {
  "tests.unit.query_markers_spec",
  "tests.unit.diag_parser_spec",
  "tests.unit.query_output_spec",
  "tests.integration.run_spec",
}

local function sorted_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local total = 0
local failed = 0
local skipped = 0
local skip_prefix = helpers.skip_prefix()

for _, module_name in ipairs(modules) do
  local ok, cases_or_err = pcall(require, module_name)
  if not ok then
    failed = failed + 1
    io.stderr:write(string.format("✗ %s (load error)\n", module_name))
    io.stderr:write(cases_or_err .. "\n")
    goto continue
  end

  local cases = cases_or_err
  for _, case_name in ipairs(sorted_keys(cases)) do
    total = total + 1
    local fn = cases[case_name]

    local run_ok, err = pcall(fn, helpers)
    if run_ok then
      io.stdout:write(string.format("✓ %s :: %s\n", module_name, case_name))
      goto next_case
    end

    local msg = tostring(err)
    if msg:find(skip_prefix, 1, true) == 1 then
      skipped = skipped + 1
      msg = msg:sub(#skip_prefix + 1)
      io.stdout:write(string.format("↷ %s :: %s (%s)\n", module_name, case_name, msg))
      goto next_case
    end

    failed = failed + 1
    io.stderr:write(string.format("✗ %s :: %s\n", module_name, case_name))
    io.stderr:write(msg .. "\n")

    ::next_case::
  end

  ::continue::
end

local passed = total - failed - skipped

if failed > 0 then
  io.stderr:write(string.format("\n%d failed, %d passed, %d skipped (%d total)\n", failed, passed, skipped, total))
  vim.cmd("cquit 1")
  return
end

io.stdout:write(string.format("\n%d passed, %d skipped (%d total)\n", passed, skipped, total))
vim.cmd.quitall({ bang = true })
