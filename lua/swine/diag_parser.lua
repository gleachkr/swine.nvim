local M = {}

local function split_lines(s)
  if not s or s == "" then
    return {}
  end

  return vim.split(s, "\n", { plain = true, trimempty = true })
end

local function normalize_file_ref(raw)
  if type(raw) ~= "string" then
    return raw
  end

  local stripped = raw:match("^%[[^%]]+%]%s+(.+)$")
  return stripped or raw
end

local function same_file(a, b)
  return vim.fs.normalize(normalize_file_ref(a)) == vim.fs.normalize(b)
end

function M.parse(file, text, source)
  local diags = {}
  local diag_source = source or "swipl"

  for _, line in ipairs(split_lines(text)) do
    local f1, l1, c1, m1 = line:match("^ERROR:%s+(.+):(%d+):(%d+):%s+(.+)$")
    if f1 and same_file(f1, file) then
      table.insert(diags, {
        lnum = tonumber(l1) - 1,
        col = tonumber(c1) - 1,
        message = m1,
        source = diag_source,
        severity = vim.diagnostic.severity.ERROR,
      })
      goto continue
    end

    local f2, l2, m2 = line:match("^ERROR:%s+(.+):(%d+):%s+(.+)$")
    if f2 and same_file(f2, file) then
      table.insert(diags, {
        lnum = tonumber(l2) - 1,
        col = 0,
        message = m2,
        source = diag_source,
        severity = vim.diagnostic.severity.ERROR,
      })
      goto continue
    end

    local f3, l3, m3 = line:match("^Warning:%s+(.+):(%d+):%s+(.+)$")
    if f3 and same_file(f3, file) then
      table.insert(diags, {
        lnum = tonumber(l3) - 1,
        col = 0,
        message = m3,
        source = diag_source,
        severity = vim.diagnostic.severity.WARN,
      })
      goto continue
    end

    ::continue::
  end

  return diags
end

return M
