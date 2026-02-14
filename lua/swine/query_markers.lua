local M = {}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

function M.parse(line, hard_max)
  local limit = hard_max or 1

  local n_raw, q_num = line:match("^%s*%%(%d+)%?%s*(.-)%s*$")
  if n_raw and q_num and q_num ~= "" then
    local n = clamp(tonumber(n_raw) or 1, 1, limit)
    q_num = q_num:gsub("%.%s*$", "")
    if q_num ~= "" then
      return q_num, n
    end
  end

  local marks, q_marks = line:match("^%s*%%(%?+)%s*(.-)%s*$")
  if marks and q_marks and q_marks ~= "" then
    local n = clamp(#marks, 1, limit)
    q_marks = q_marks:gsub("%.%s*$", "")
    if q_marks ~= "" then
      return q_marks, n
    end
  end

  return nil, nil
end

function M.collect_from_lines(lines, hard_max)
  local out = {}
  local limit = hard_max or 1

  for i, line in ipairs(lines) do
    local query, max_solutions = M.parse(line, limit)
    if query and query ~= "" then
      table.insert(out, {
        lnum = i - 1,
        query = query,
        max_solutions = max_solutions,
      })
    end
  end

  return out
end

return M
