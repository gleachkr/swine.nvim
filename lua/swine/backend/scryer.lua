local query_output = require("swine.query_output")

local M = {
  id = "scryer",
  label = "Scryer Prolog",
  executable = "scryer-prolog",
}

local function split_lines(s)
  if not s or s == "" then
    return {}
  end

  return vim.split(s, "\n", { plain = true, trimempty = true })
end

local function normalize_file_ref(raw)
  if type(raw) ~= "string" then
    return nil
  end

  local unquoted = raw:match('^"(.+)"$') or raw
  return vim.fs.normalize(unquoted)
end

local function same_file(file_ref, file)
  local lhs = normalize_file_ref(file_ref)
  if not lhs then
    return false
  end

  local rhs = vim.fs.normalize(file)
  if lhs == rhs then
    return true
  end

  return vim.fs.basename(lhs) == vim.fs.basename(rhs)
end

local function error_diag(message, lnum)
  return {
    lnum = math.max(0, (lnum or 1) - 1),
    col = 0,
    message = message,
    source = M.executable,
    severity = vim.diagnostic.severity.ERROR,
  }
end

local function warning_diag(message, lnum)
  return {
    lnum = math.max(0, (lnum or 1) - 1),
    col = 0,
    message = message,
    source = M.executable,
    severity = vim.diagnostic.severity.WARN,
  }
end

local function parse_warning(line, file)
  local message, lnum, file_ref = line:match("^%%%s*Warning:%s+(.+)%s+at line%s+(%d+)%s+of%s+(.+)$")

  if not message or not lnum or not file_ref then
    return nil
  end

  if not same_file(file_ref, file) then
    return nil
  end

  return warning_diag(message, tonumber(lnum))
end

local function parse_read_term_error(line)
  local term, lnum = line:match("^%s*error%((.+),read_term/%d+:(%d+)%)%.?$")

  if not term or not lnum then
    return nil
  end

  return error_diag(term, tonumber(lnum))
end

local function parse_load_error(line)
  local term = line:match("^%s*error%((.+),load/%d+%)%.?$")
  if not term then
    return nil
  end

  return error_diag(term, 1)
end

local function parse_generic_error(line)
  local term = line:match("^%s*error%((.+)%)%.?$")
  if not term then
    return nil
  end

  return error_diag(term, 1)
end

local function query_code_list(query)
  local codes = {}

  for i = 1, #query do
    table.insert(codes, string.byte(query, i))
  end

  if #codes == 0 or codes[#codes] ~= string.byte(".") then
    table.insert(codes, string.byte("."))
  end

  local out = {}
  for _, code in ipairs(codes) do
    table.insert(out, tostring(code))
  end

  return table.concat(out, ",")
end

local function build_query_goal(query, max_solutions)
  local codes = query_code_list(query)

  return string.format(
    table.concat({
      "catch((",
      "use_module(library(charsio)),",
      "use_module(library(lists)),",
      "atom_codes(QAtom,[%s]),",
      "atom_chars(QAtom,QChars),",
      "read_from_chars(QChars,Q),",
      "term_variables(Q,Vars),",
      "findall(Vars,Q,Sols),",
      '(Sols==[]->format("PLNB_FALSE~n",[]);true),',
      "(nth1(I,Sols,SVNs),I=<%d,",
      '(SVNs==[]->format("PLNB_SOL ~d true~n",[I]);',
      'format("PLNB_SOL ~d ~q~n",[I,SVNs])),fail;true)',
      '),E,format("PLNB_ERROR ~q~n",[E])),',
      "halt",
    }),
    codes,
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
    file,
    "-g",
    "halt",
  }
end

function M.parse_load_diags(file, text)
  local diags = {}

  for _, line in ipairs(split_lines(text)) do
    local diag = parse_warning(line, file)
      or parse_read_term_error(line)
      or parse_load_error(line)
      or parse_generic_error(line)

    if diag then
      table.insert(diags, diag)
    end
  end

  return diags
end

function M.build_query_cmd(file, query, max_solutions)
  return {
    M.executable,
    file,
    "-g",
    build_query_goal(query, max_solutions),
  }
end

function M.parse_query_output(text, obj, timeout_ms)
  return query_output.parse(text, obj, timeout_ms)
end

function M.is_timeout_result(obj, text)
  return query_output.is_timeout_result(obj, text)
end

return M
