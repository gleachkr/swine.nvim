local diag_parser = require("swine.diag_parser")
local query_output = require("swine.query_output")

local M = {
  id = "swi",
  label = "SWI-Prolog",
  executable = "swipl",
}

local function build_query_goal(max_solutions, include_output)
  local verbose_setup = ""
  if include_output then
    verbose_setup = "set_prolog_flag(verbose,normal),"
  end

  return string.format(
    table.concat({
      "%s",
      "current_prolog_flag(argv,Argv),",
      "(Argv=[QAtom|_]->true;QAtom=''),",
      "catch((",
      "read_term_from_atom(QAtom,Q,[variable_names(VNs)]),",
      "findnsols(%d,VNs,Q,Sols),",
      "(Sols==[]->writeln('PLNB_FALSE');",
      "forall(nth1(I,Sols,SVNs),",
      "(SVNs==[]->format('PLNB_SOL ~d true~n',[I]);",
      "format('PLNB_SOL ~d ~q~n',[I,SVNs]))))",
      "),E,format('PLNB_ERROR ~q~n',[E]))",
    }),
    verbose_setup,
    max_solutions
  )
end

function M.is_available()
  return vim.fn.exepath(M.executable) ~= ""
end

function M.missing_message()
  return string.format("%s not found in PATH", M.executable)
end

function M.build_load_cmd(file)
  return {
    M.executable,
    "-q",
    "-f",
    "none",
    "-l",
    file,
    "-g",
    "halt",
  }
end

function M.parse_load_diags(file, text)
  return diag_parser.parse(file, text, M.executable)
end

function M.build_query_cmd(file, query, max_solutions, opts)
  local include_output = type(opts) == "table" and opts.include_output == true

  return {
    M.executable,
    "-q",
    "-f",
    "none",
    "-l",
    file,
    "-g",
    build_query_goal(max_solutions, include_output),
    "-t",
    "halt",
    "--",
    query,
  }
end

function M.parse_query_output(text, obj, timeout_ms, parse_opts)
  return query_output.parse(text, obj, timeout_ms, parse_opts)
end

function M.is_timeout_result(obj, text)
  return query_output.is_timeout_result(obj, text)
end

return M
