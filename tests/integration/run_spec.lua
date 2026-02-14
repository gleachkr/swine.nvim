local swine = require("swine")

swine.setup({
  run_on_save = false,
  load_timeout_ms = 3000,
  query_timeout_ms = 3000,
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
        return mark ~= nil
          and mark[4] ~= nil
          and mark[4].virt_lines ~= nil
          and #mark[4].virt_lines >= 2
      end, 4000, 20, "expected query virtual lines")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = t.find_mark_by_lnum(marks, 2)
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")

      t.contains(joined, "X = alpha")
      t.contains(joined, "X = beta")
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

      vim.system = original_system

      if ok then
        return
      end

      error(err, 0)
    end)
  end,
}
