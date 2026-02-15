local swine = require("swine")

swine.setup({
  run_on_save = false,
  backend = "scryer",
  load_timeout_ms = 3000,
  query_timeout_ms = 3000,
})

local function require_scryer(t)
  if vim.fn.exepath("scryer-prolog") ~= "" then
    return
  end

  t.skip("scryer-prolog not found in PATH")
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

local function has_diag(diags, severity, needle)
  for _, diag in ipairs(diags) do
    if diag.severity == severity then
      if not needle or string.find(diag.message, needle, 1, true) then
        return true
      end
    end
  end

  return false
end

return {
  ["Scryer backend sets diagnostics for syntax errors"] = function(t)
    require_scryer(t)

    with_prolog_buffer(t, {
      "ok_fact(a).",
      "broken(.",
    }, function(buf)
      swine.run(buf)

      local ns_diag = get_namespace("swine_diag")
      t.ok(ns_diag ~= nil, "missing swine_diag namespace")

      t.wait_for(function()
        return #vim.diagnostic.get(buf, { namespace = ns_diag }) > 0
      end, 6000, 20, "expected diagnostics after SwineRun")

      local diags = vim.diagnostic.get(buf, { namespace = ns_diag })
      t.ok(has_diag(diags, vim.diagnostic.severity.ERROR, "syntax_error"), "expected syntax error diagnostic")
    end)
  end,

  ["Scryer backend sets diagnostics for singleton warnings"] = function(t)
    require_scryer(t)

    with_prolog_buffer(t, {
      "p(X) :- true.",
    }, function(buf)
      swine.run(buf)

      local ns_diag = get_namespace("swine_diag")
      t.ok(ns_diag ~= nil, "missing swine_diag namespace")

      t.wait_for(function()
        return #vim.diagnostic.get(buf, { namespace = ns_diag }) > 0
      end, 6000, 20, "expected diagnostics after SwineRun")

      local diags = vim.diagnostic.get(buf, { namespace = ns_diag })
      t.ok(has_diag(diags, vim.diagnostic.severity.WARN, "singleton"), "expected singleton warning diagnostic")
    end)
  end,

  ["Scryer backend renders query result virtual lines"] = function(t)
    require_scryer(t)

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
        return mark ~= nil and mark[4] ~= nil and mark[4].virt_lines ~= nil
      end, 6000, 20, "expected query virtual lines")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = t.find_mark_by_lnum(marks, 2)
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")

      t.contains(joined, "alpha")
      t.contains(joined, "beta")
    end)
  end,

  ["Scryer backend renders false for unsatisfied query"] = function(t)
    require_scryer(t)

    with_prolog_buffer(t, {
      "q_item(alpha).",
      "%? q_item(beta).",
    }, function(buf)
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
        return joined:find("false", 1, true) ~= nil
      end, 6000, 20, "expected false result for unsatisfied query")

      local marks = t.buf_extmarks(buf, ns_qres)
      local mark = t.find_mark_by_lnum(marks, 1)
      local text_lines = t.virt_lines_to_text(mark[4].virt_lines)
      local joined = table.concat(text_lines, "\n")

      t.contains(joined, "false")
    end)
  end,
}
