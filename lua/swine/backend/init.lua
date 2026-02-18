local query_output = require("swine.query_output")

local M = {}

local BUILTINS = {
  swi = require("swine.backend.swi"),
  scryer = require("swine.backend.scryer"),
}

local ALIASES = {
  swipl = "swi",
}

local REQUIRED_FUNCS = {
  "build_load_cmd",
  "build_query_cmd",
  "parse_load_diags",
  "parse_query_output",
  "is_timeout_result",
  "is_available",
  "missing_message",
}

local function with_defaults(raw)
  local backend = vim.deepcopy(raw)

  backend.id = backend.id or "custom"
  backend.label = backend.label or backend.id

  if type(backend.executable) == "string" and backend.executable ~= "" then
    if type(backend.is_available) ~= "function" then
      backend.is_available = function()
        return vim.fn.exepath(backend.executable) ~= ""
      end
    end

    if type(backend.missing_message) ~= "function" then
      backend.missing_message = function()
        return string.format("%s not found in PATH", backend.executable)
      end
    end
  end

  if type(backend.parse_load_diags) ~= "function" then
    backend.parse_load_diags = function()
      return {}
    end
  end

  if type(backend.parse_query_output) ~= "function" then
    backend.parse_query_output = function(text, obj, timeout_ms, parse_opts)
      return query_output.parse(text, obj, timeout_ms, parse_opts)
    end
  end

  if type(backend.is_timeout_result) ~= "function" then
    backend.is_timeout_result = function(obj, text)
      return query_output.is_timeout_result(obj, text)
    end
  end

  return backend
end

local function validate_backend(backend)
  if type(backend) ~= "table" then
    return nil, "backend must be a table or backend id"
  end

  if type(backend.id) ~= "string" or backend.id == "" then
    return nil, "backend.id must be a non-empty string"
  end

  if type(backend.label) ~= "string" or backend.label == "" then
    return nil, "backend.label must be a non-empty string"
  end

  for _, fn_name in ipairs(REQUIRED_FUNCS) do
    if type(backend[fn_name]) ~= "function" then
      return nil, string.format("backend.%s must be a function", fn_name)
    end
  end

  return backend
end

local function resolve_builtin_id(id)
  local key = string.lower(id)
  return ALIASES[key] or key
end

function M.resolve(spec)
  local raw

  if spec == nil then
    raw = BUILTINS.swi
  elseif type(spec) == "string" then
    local id = resolve_builtin_id(spec)
    raw = BUILTINS[id]

    if not raw then
      local known = vim.tbl_keys(BUILTINS)
      table.sort(known)

      local msg = string.format("unknown backend '%s' (known: %s)", spec, table.concat(known, ", "))

      return nil, msg
    end
  elseif type(spec) == "table" then
    raw = spec
  else
    return nil, "backend must be nil, string, or table"
  end

  local backend = with_defaults(raw)
  return validate_backend(backend)
end

function M.builtin_ids()
  local out = vim.tbl_keys(BUILTINS)
  table.sort(out)
  return out
end

return M
