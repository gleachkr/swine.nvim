local M = {}

local function split_lines(s)
  if not s or s == "" then
    return {}
  end

  return vim.split(s, "\n", { plain = true, trimempty = true })
end

local function first_nonempty_line(s)
  for _, line in ipairs(split_lines(s)) do
    if line:match("%S") then
      return line
    end
  end

  return nil
end

function M.is_timeout_result(obj, text)
  if not obj then
    return false
  end

  if obj.code == 124 then
    return true
  end

  local hay = (obj.stderr or "") .. "\n" .. (text or "")
  hay = hay:lower()
  return hay:find("timed out", 1, true) ~= nil
end

local function normalize_payload(payload)
  local value = payload or ""

  if value:sub(1, 1) == "[" and value:sub(-1) == "]" then
    value = value:sub(2, -2)
  end

  value = value:gsub("'([%a_][%w_]*)'=", "%1 = ")
  value = value:gsub(",", ", ")
  value = value:gsub("%s+", " ")
  value = value:gsub("^%s+", "")
  value = value:gsub("%s+$", "")

  if value == "" then
    return "true"
  end

  return value
end

local function parse_machine_line(line)
  local idx, payload = line:match("^PLNB_SOL%s+(%d+)%s+(.*)$")
  if idx then
    return "sol", tonumber(idx), payload
  end

  if line == "PLNB_FALSE" then
    return "false"
  end

  local e = line:match("^PLNB_ERROR%s+(.+)$")
  if e then
    return "error", e
  end

  return nil
end

local function extract_side_lines(raw)
  local out = {}

  for _, line in ipairs(split_lines(raw)) do
    local tag = parse_machine_line(line)
    if not tag then
      table.insert(out, line)
    end
  end

  return out
end

local function append_side_chunk(rows, label, kind, lines)
  if #lines == 0 then
    return
  end

  table.insert(rows, {
    text = label,
    kind = kind,
    lead = true,
  })

  for _, line in ipairs(lines) do
    table.insert(rows, {
      text = line,
      kind = kind,
    })
  end
end

function M.parse(text, obj, timeout_ms, opts)
  local options = opts or {}
  local include_output = options.include_output == true
  local stdout = options.stdout
  local stderr = options.stderr
  local stream_split = stdout ~= nil or stderr ~= nil

  local sols = {}
  local side_rows = {}
  local loose_side_lines = {}
  local saw_false = false
  local err = nil

  if include_output and stream_split then
    append_side_chunk(side_rows, "stdout", "info", extract_side_lines(stdout))
    append_side_chunk(side_rows, "stderr", "warn", extract_side_lines(stderr))
  end

  local function with_side_output(rows)
    if not include_output or #side_rows == 0 then
      return rows
    end

    local out = {}
    vim.list_extend(out, side_rows)

    if #rows > 0 then
      table.insert(out, {
        text = "result",
        kind = "info",
        lead = true,
      })
    end

    vim.list_extend(out, rows)
    return out
  end

  for _, line in ipairs(split_lines(text)) do
    local tag, a, b = parse_machine_line(line)

    if tag == "sol" then
      table.insert(sols, {
        idx = a,
        payload = b,
      })
      goto continue
    end

    if tag == "false" then
      saw_false = true
      goto continue
    end

    if tag == "error" then
      err = a
      goto continue
    end

    if include_output and not stream_split then
      table.insert(loose_side_lines, line)
    end

    ::continue::
  end

  if include_output and not stream_split then
    append_side_chunk(side_rows, "output", "info", loose_side_lines)
  end

  if err then
    return with_side_output({
      {
        text = "error: " .. err,
        kind = "error",
      },
    })
  end

  if saw_false then
    return with_side_output({
      {
        text = "false",
        kind = "warn",
      },
    })
  end

  if #sols > 0 then
    local out = {}
    local many = #sols > 1

    for _, s in ipairs(sols) do
      local payload = normalize_payload(s.payload)
      local line = payload

      if many then
        line = string.format("%d) %s", s.idx, payload)
      end

      table.insert(out, {
        text = line,
        kind = "hint",
      })
    end

    return with_side_output(out)
  end

  if M.is_timeout_result(obj, text) then
    return with_side_output({
      {
        text = string.format("timeout after %d ms", timeout_ms),
        kind = "error",
      },
    })
  end

  if obj and obj.code and obj.code ~= 0 then
    local detail = first_nonempty_line(text) or "swipl query failed"
    return with_side_output({
      {
        text = string.format("error (%d): %s", obj.code, detail),
        kind = "error",
      },
    })
  end

  return with_side_output({
    {
      text = "?",
      kind = "warn",
    },
  })
end

return M
