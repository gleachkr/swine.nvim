local M = {}

local SKIP_PREFIX = "__SWINE_SKIP__"

local function render(v)
  return vim.inspect(v, { newline = "", indent = "" })
end

function M.eq(actual, expected, msg)
  if vim.deep_equal(actual, expected) then
    return
  end

  local detail = {
    msg or "values are not equal",
    "expected: " .. render(expected),
    "actual:   " .. render(actual),
  }
  error(table.concat(detail, "\n"), 2)
end

function M.ok(value, msg)
  if value then
    return
  end

  error(msg or "expected truthy value", 2)
end

function M.is_nil(value, msg)
  if value == nil then
    return
  end

  error(msg or ("expected nil, got " .. render(value)), 2)
end

function M.contains(haystack, needle, msg)
  if type(haystack) ~= "string" then
    error("contains() expects haystack string", 2)
  end

  if type(needle) ~= "string" then
    error("contains() expects needle string", 2)
  end

  if haystack:find(needle, 1, true) then
    return
  end

  local detail = msg or string.format("expected substring %s in %s", render(needle), render(haystack))
  error(detail, 2)
end

function M.skip(msg)
  error(SKIP_PREFIX .. (msg or "skipped"), 0)
end

function M.skip_prefix()
  return SKIP_PREFIX
end

function M.wait_for(predicate, timeout_ms, interval_ms, msg)
  local timeout = timeout_ms or 2000
  local interval = interval_ms or 20
  local ok = vim.wait(timeout, predicate, interval)

  if ok then
    return
  end

  local detail = msg or string.format("wait_for timed out after %d ms", timeout)
  error(detail, 2)
end

function M.write_temp_file(lines, suffix)
  local path = vim.fn.tempname() .. (suffix or ".pl")
  vim.fn.writefile(lines, path)
  return vim.fs.normalize(path)
end

function M.create_file_buffer(path, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.fn.writefile(lines, path)
  return buf
end

function M.buf_extmarks(buf, namespace)
  return vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
end

function M.find_mark_by_lnum(marks, lnum)
  for _, mark in ipairs(marks) do
    if mark[2] == lnum then
      return mark
    end
  end

  return nil
end

function M.virt_lines_to_text(virt_lines)
  local out = {}

  for _, line_chunks in ipairs(virt_lines or {}) do
    local chunks = {}
    for _, chunk in ipairs(line_chunks) do
      table.insert(chunks, chunk[1])
    end

    local line = table.concat(chunks)
    line = line:gsub("%s+$", "")
    table.insert(out, line)
  end

  return out
end

return M
