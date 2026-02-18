local M = {}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function parse_start_marker(line, hard_max)
  local limit = hard_max or 1

  local n_raw, q_num = line:match("^%s*%%(%d+)%?%s*(.-)%s*$")
  if n_raw then
    local n = clamp(tonumber(n_raw) or 1, 1, limit)
    return q_num, n, false
  end

  local marks, q_marks = line:match("^%s*%%(%?+)%s*(.-)%s*$")
  if marks then
    local n = clamp(#marks, 1, limit)
    return q_marks, n, false
  end

  local q_output = line:match("^%s*%%!%s*(.-)%s*$")
  if q_output ~= nil then
    return q_output, 1, true
  end

  return nil, nil, nil
end

local function parse_continuation_marker(line)
  local q_cont = line:match("^%s*%%|%s*(.-)%s*$")
  if q_cont == nil then
    return nil
  end

  return q_cont
end

local function finalize_query(parts)
  local query = table.concat(parts, "\n")
  query = query:gsub("%.%s*$", "")

  if query:match("^%s*$") then
    return nil
  end

  return query
end

function M.parse(line, hard_max)
  local query, n, include_output = parse_start_marker(line, hard_max)
  if query == nil then
    return nil, nil, nil
  end

  query = finalize_query({ query })
  if query == nil then
    return nil, nil, nil
  end

  return query, n, include_output
end

function M.collect_from_lines(lines, hard_max)
  local out = {}
  local limit = hard_max or 1
  local i = 1

  while i <= #lines do
    local query, max_solutions, include_output = parse_start_marker(lines[i], limit)
    if query == nil then
      i = i + 1
      goto continue
    end

    local parts = {}
    if query ~= "" then
      table.insert(parts, query)
    end
    local j = i + 1

    while j <= #lines do
      local q_cont = parse_continuation_marker(lines[j])
      if q_cont == nil then
        break
      end

      table.insert(parts, q_cont)
      j = j + 1
    end

    local full_query = finalize_query(parts)
    if full_query ~= nil then
      local last_lnum = j - 2
      table.insert(out, {
        lnum = last_lnum,
        query = full_query,
        max_solutions = max_solutions,
        include_output = include_output and true or nil,
      })
    end

    i = j

    ::continue::
  end

  return out
end

return M
