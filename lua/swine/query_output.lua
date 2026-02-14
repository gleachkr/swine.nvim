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

function M.parse(text, obj, timeout_ms)
  local sols = {}
  local saw_false = false
  local err = nil

  for _, line in ipairs(split_lines(text)) do
    local idx, payload = line:match("^PLNB_SOL%s+(%d+)%s+(.*)$")
    if idx then
      table.insert(sols, {
        idx = tonumber(idx),
        payload = payload,
      })
      goto continue
    end

    if line == "PLNB_FALSE" then
      saw_false = true
      goto continue
    end

    local e = line:match("^PLNB_ERROR%s+(.+)$")
    if e then
      err = e
      goto continue
    end

    ::continue::
  end

  if err then
    return {
      {
        text = "error: " .. err,
        kind = "error",
      },
    }
  end

  if saw_false then
    return {
      {
        text = "false",
        kind = "warn",
      },
    }
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

    return out
  end

  if M.is_timeout_result(obj, text) then
    return {
      {
        text = string.format("timeout after %d ms", timeout_ms),
        kind = "error",
      },
    }
  end

  if obj and obj.code and obj.code ~= 0 then
    local detail = first_nonempty_line(text) or "swipl query failed"
    return {
      {
        text = string.format("error (%d): %s", obj.code, detail),
        kind = "error",
      },
    }
  end

  return {
    {
      text = "?",
      kind = "warn",
    },
  }
end

return M
