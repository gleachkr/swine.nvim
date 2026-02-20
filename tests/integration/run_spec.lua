local swine = require("swine")

swine.setup({
  run_on_save = false,
  load_timeout_ms = 3000,
  query_timeout_ms = 3000,
  query_stale_ms = 500,
})

local function require_swipl(t)
  if vim.fn.exepath("swipl") ~= "" then
    return
  end

  t.skip("swipl not found in PATH")
end

local function with_prolog_buffer(t, lines, fn)
  local path = t.write_temp_file(lines, ".pl")
  local buf = t.create_file_buffer(path, lines)

  local ok, err = xpcall(function()
    fn(buf, path)
  end, debug.traceback)

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(swine.clear, buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  pcall(os.remove, path)

  if ok then
    return
  end

  error(err, 0)
end

local function get_namespace(name)
  return vim.api.nvim_get_namespaces()[name]
end

local function find_mark_by_id(marks, id)
  for _, mark in ipairs(marks) do
    if mark[1] == id then
      return mark
    end
  end

  return nil
end

local function virt_text_to_text(virt_text)
  local out = {}

  for _, chunk in ipairs(virt_text or {}) do
    table.insert(out, chunk[1])
  end

  return table.concat(out)
end

local function find_mark_with_text(t, marks, needle)
  for _, mark in ipairs(marks) do
    local details = mark[4]

    if details and details.virt_lines then
      local text_lines = t.virt_lines_to_text(details.virt_lines)
      local joined = table.concat(text_lines, "\n")
      if joined:find(needle, 1, true) then
        return mark
      end
    end

    if details and details.virt_text then
      local text = virt_text_to_text(details.virt_text)
      if text:find(needle, 1, true) then
        return mark
      end
    end
  end

  return nil
end

local function first_virt_line_hl(mark)
  local details = mark and mark[4]
  if not details or not details.virt_lines then
    return nil
  end

  local line = details.virt_lines[1]
  if type(line) ~= "table" then
    return nil
  end

  local chunk = line[1]
  if type(chunk) ~= "table" then
    return nil
  end

  return chunk[2]
end

return {
  ["SwineRun sets diagnostics for load errors"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "ok_fact(a).",
      "broken(.",
    }, function(buf)
      swine.run(buf)

      local ns_diag = get_namespace("swine_diag")
      t.ok(ns_diag ~= nil, "missing swine_diag namespace")

      t.wait_for(function()
        return #vim.diagnostic.get(buf, { namespace = ns_diag }) > 0
      end, 4000, 20, "expected diagnostics after SwineRun")

      local diags = vim.diagnostic.get(buf, { namespace = ns_diag })
      local has_error = false

      for _, d in ipairs(diags) do
        if d.severity == vim.diagnostic.severity.ERROR then
          has_error = true
          break
        end
      end

      t.ok(has_error, "expected at least one error diagnostic")
    end)
  end,

  ["SwineRun renders status as virt_text on first buffer line"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "ready.",
    }, function(buf)
      swine.run(buf)

      local ns_qres = get_namespace("swine_qres")
      t.ok(ns_qres ~= nil, "missing swine_qres namespace")

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        local mark = find_mark_with_text(t, marks, "✓ loaded")
        return mark ~= nil and mark[2] == 0 and mark[4] and mark[4].virt_text ~= nil
      end, 4000, 20, "expected status virt_text on first buffer line")
    end)
  end,

  ["SwineRun renders query result virtual lines"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "q_item(alpha).",
      "q_item(beta).",
      "%2? q_item(X).",
    }, function(buf)
      swine.run(buf)

      local ns_qres = get_namespace("swine_qres")
      t.ok(ns_qres ~= nil, "missing swine_qres namespace")

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        local mark = t.find_mark_by_lnum(marks, 2)
        return mark ~= nil and mark[4] ~= nil and mark[4].virt_lines ~= nil and #mark[4].virt_lines >= 2
      end, 4000, 20, "expected query virtual lines")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = t.find_mark_by_lnum(marks, 2)
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")

      t.contains(joined, "X = alpha")
      t.contains(joined, "X = beta")
    end)
  end,

  ["SwineRun renders side-effect text for %! markers"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "say_hi :- writeln('hi from side effect').",
      "%! say_hi.",
    }, function(buf)
      swine.run(buf)

      local ns_qres = get_namespace("swine_qres")
      t.ok(ns_qres ~= nil, "missing swine_qres namespace")

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        local mark = t.find_mark_by_lnum(marks, 1)
        return mark ~= nil and mark[4] ~= nil and mark[4].virt_lines ~= nil and #mark[4].virt_lines >= 2
      end, 4000, 20, "expected %! query virtual lines")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = t.find_mark_by_lnum(marks, 1)
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")

      t.contains(joined, "⇒ stdout")
      t.contains(joined, "hi from side effect")
      t.contains(joined, "⇒ result")
      t.contains(joined, "true")
    end)
  end,

  ["SwineRun %! renders message output for license/0"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "%! license.",
    }, function(buf)
      swine.run(buf)

      local ns_qres = get_namespace("swine_qres")
      t.ok(ns_qres ~= nil, "missing swine_qres namespace")

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        local mark = find_mark_with_text(t, marks, "Simplified BSD license")
        return mark ~= nil
      end, 4000, 20, "expected license text in %! output")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = find_mark_with_text(t, marks, "Simplified BSD license")
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")

      t.contains(joined, "⇒ stderr")
      t.contains(joined, "Simplified BSD license")
      t.contains(joined, "⇒ result")
      t.contains(joined, "true")
    end)
  end,

  ["query result cell moves up when deleting line above it"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "q_item(alpha).",
      "%? q_item(X).",
      "after_query_line.",
    }, function(buf)
      swine.run(buf)

      local ns_qres = get_namespace("swine_qres")
      t.ok(ns_qres ~= nil, "missing swine_qres namespace")

      local query_mark

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        query_mark = find_mark_with_text(t, marks, "X = alpha")
        return query_mark ~= nil and query_mark[4] and query_mark[4].virt_lines_above == true
      end, 4000, 20, "expected query virtual lines anchored above next line")

      local mark_id = query_mark[1]
      local original_lnum = query_mark[2]

      vim.api.nvim_buf_set_lines(buf, 1, 2, false, {})

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        local moved = find_mark_by_id(marks, mark_id)
        return moved ~= nil and moved[2] == (original_lnum - 1)
      end, 1000, 20, "expected query mark to shift up after deleting line above")
    end)
  end,

  ["SwineRun supports multiline %| query markers"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "q_item(alpha).",
      "q_item(beta).",
      "%? q_item(X),",
      "%| X \\= beta.",
    }, function(buf)
      swine.run(buf)

      local ns_qres = get_namespace("swine_qres")
      t.ok(ns_qres ~= nil, "missing swine_qres namespace")

      t.wait_for(function()
        local marks = t.buf_extmarks(buf, ns_qres)
        local mark = t.find_mark_by_lnum(marks, 3)
        return mark ~= nil and mark[4] ~= nil and mark[4].virt_lines ~= nil and #mark[4].virt_lines >= 1
      end, 4000, 20, "expected query virtual lines")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = t.find_mark_by_lnum(marks, 3)
      local mark_id = mark[1]
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")
      local line = vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1] or ""

      t.contains(joined, "X = alpha")
      t.eq(mark[3], #line)

      vim.api.nvim_buf_set_text(buf, 3, 5, 3, 5, { "", "" })

      t.wait_for(function()
        local moved_marks = t.buf_extmarks(buf, ns_qres)
        local moved = find_mark_by_id(moved_marks, mark_id)
        return moved ~= nil and moved[2] == 4
      end, 1000, 20, "expected query mark to follow split line")
    end)
  end,

  ["long-running queries dim previous result cells"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "q_item(first).",
      "%? q_item(X).",
    }, function(buf)
      local original_system = vim.system
      local query_calls = 0

      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _opts, cb)
        local has_query = false

        for _, arg in ipairs(cmd) do
          if arg == "--" then
            has_query = true
            break
          end
        end

        local delay_ms = 10
        local obj = {
          code = 0,
          stdout = "",
          stderr = "",
        }

        if has_query then
          query_calls = query_calls + 1
          if query_calls == 1 then
            obj.stdout = "PLNB_SOL 1 ['X'=first]\n"
          else
            delay_ms = 900
            obj.stdout = "PLNB_SOL 1 ['X'=second]\n"
          end
        end

        vim.defer_fn(function()
          cb(obj)
        end, delay_ms)

        return {
          wait = function()
            return obj
          end,
        }
      end

      local ok, err = xpcall(function()
        swine.run(buf)

        local ns_qres = get_namespace("swine_qres")
        t.ok(ns_qres ~= nil, "missing swine_qres namespace")

        t.wait_for(function()
          local marks = t.buf_extmarks(buf, ns_qres)
          local mark = t.find_mark_by_lnum(marks, 1)
          if not mark or not mark[4] or not mark[4].virt_lines then
            return false
          end

          local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
          local joined = table.concat(text_lines, "\n")
          return joined:find("X = first", 1, true) ~= nil
        end, 2000, 20, "expected first query result")

        swine.run(buf)

        t.wait_for(function()
          local marks = t.buf_extmarks(buf, ns_qres)
          local mark = t.find_mark_by_lnum(marks, 1)
          if not mark or not mark[4] or not mark[4].virt_lines then
            return false
          end

          local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
          local joined = table.concat(text_lines, "\n")
          if joined:find("X = first", 1, true) == nil then
            return false
          end

          local group = first_virt_line_hl(mark)
          return group == "SwineVirtStale" or group == "Comment"
        end, 1500, 20, "expected stale query cell dimming")

        t.wait_for(function()
          local marks = t.buf_extmarks(buf, ns_qres)
          local mark = t.find_mark_by_lnum(marks, 1)
          if not mark or not mark[4] or not mark[4].virt_lines then
            return false
          end

          local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
          local joined = table.concat(text_lines, "\n")
          if joined:find("X = second", 1, true) == nil then
            return false
          end

          local group = first_virt_line_hl(mark)
          return group ~= "SwineVirtStale" and group ~= "Comment"
        end, 2000, 20, "expected stale dimming to clear on completion")
      end, debug.traceback)

      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = original_system

      if ok then
        return
      end

      error(err, 0)
    end)
  end,

  ["stale async run does not clobber newer run"] = function(t)
    require_swipl(t)

    with_prolog_buffer(t, {
      "race_fact(fresh).",
      "%? race_fact(X).",
    }, function(buf, path)
      local original_system = vim.system
      local load_calls = 0

      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _opts, cb)
        local has_query = false

        for _, arg in ipairs(cmd) do
          if arg == "--" then
            has_query = true
            break
          end
        end

        local delay_ms
        local obj

        if has_query then
          delay_ms = 10
          obj = {
            code = 0,
            stdout = "PLNB_SOL 1 ['X'=fresh]\n",
            stderr = "",
          }
        else
          load_calls = load_calls + 1

          if load_calls == 1 then
            delay_ms = 150
            obj = {
              code = 0,
              stdout = "",
              stderr = string.format("ERROR: %s:1: stale error", path),
            }
          else
            delay_ms = 20
            obj = {
              code = 0,
              stdout = "",
              stderr = "",
            }
          end
        end

        vim.defer_fn(function()
          cb(obj)
        end, delay_ms)

        return {
          wait = function()
            return obj
          end,
        }
      end

      local ok, err = xpcall(function()
        swine.run(buf)
        swine.run(buf)

        local ns_diag = get_namespace("swine_diag")
        local ns_qres = get_namespace("swine_qres")

        t.wait_for(function()
          local marks = t.buf_extmarks(buf, ns_qres)
          local mark = t.find_mark_by_lnum(marks, 1)
          return mark ~= nil and mark[4] and mark[4].virt_lines ~= nil
        end, 2000, 20, "expected query result from newer run")

        vim.wait(250, function()
          return false
        end, 20)

        local diags = vim.diagnostic.get(buf, { namespace = ns_diag })
        t.eq(#diags, 0, "stale load diagnostics should be ignored")

        local marks = t.buf_extmarks(buf, ns_qres)
        local mark = t.find_mark_by_lnum(marks, 1)
        local lines = t.virt_lines_to_text(mark[4].virt_lines)
        local joined = table.concat(lines, "\n")

        t.contains(joined, "X = fresh")
      end, debug.traceback)

      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = original_system

      if ok then
        return
      end

      error(err, 0)
    end)
  end,
}
