local swine = require("swine")
local backend_registry = require("swine.backend")

return {
  ["resolves default backend"] = function(t)
    local backend = assert(backend_registry.resolve(nil))

    t.eq(backend.id, "swi")
    t.ok(type(backend.build_load_cmd) == "function")
    t.ok(type(backend.build_query_cmd) == "function")
  end,

  ["resolves swipl alias to swi backend"] = function(t)
    local backend = assert(backend_registry.resolve("swipl"))
    t.eq(backend.id, "swi")
  end,

  ["resolves scryer backend"] = function(t)
    local backend = assert(backend_registry.resolve("scryer"))
    local cmd = backend.build_query_cmd("/tmp/demo.pl", "true", 3)

    t.eq(backend.id, "scryer")
    t.eq(cmd[1], "scryer-prolog")
    t.contains(cmd[4], "PLNB_SOL")
    t.contains(cmd[4], "read_from_chars")
    t.contains(cmd[4], "library(charsio)")
  end,

  ["scryer parser handles syntax errors"] = function(t)
    local backend = assert(backend_registry.resolve("scryer"))
    local file = "/tmp/demo_scryer.pl"
    local text = "   error(syntax_error(incomplete_reduction),read_term/3:2)."

    local diags = backend.parse_load_diags(file, text)

    t.eq(diags, {
      {
        lnum = 1,
        col = 0,
        message = "syntax_error(incomplete_reduction)",
        source = "scryer-prolog",
        severity = vim.diagnostic.severity.ERROR,
      },
    })
  end,

  ["scryer parser handles singleton warnings"] = function(t)
    local backend = assert(backend_registry.resolve("scryer"))
    local file = "/tmp/demo_scryer.pl"
    local text = "% Warning: singleton variables X at line 3 of demo_scryer.pl"

    local diags = backend.parse_load_diags(file, text)

    t.eq(diags, {
      {
        lnum = 2,
        col = 0,
        message = "singleton variables X",
        source = "scryer-prolog",
        severity = vim.diagnostic.severity.WARN,
      },
    })
  end,

  ["reports unknown backend ids"] = function(t)
    local backend, err = backend_registry.resolve("wat")

    t.is_nil(backend)
    t.contains(err, "unknown backend")
  end,

  ["applies defaults to custom backend tables"] = function(t)
    local backend = assert(backend_registry.resolve({
      id = "custom-test",
      label = "Custom test",
      executable = "definitely-not-on-path",
      build_load_cmd = function(file)
        return { "custom", file }
      end,
      build_query_cmd = function(file, query, max_solutions)
        return { "custom", file, query, tostring(max_solutions) }
      end,
    }))

    t.eq(backend.id, "custom-test")
    t.ok(type(backend.parse_load_diags) == "function")
    t.ok(type(backend.parse_query_output) == "function")
    t.ok(type(backend.is_timeout_result) == "function")
    t.ok(type(backend.is_available) == "function")
    t.ok(type(backend.missing_message) == "function")
  end,

  ["setup accepts backend option"] = function(t)
    swine.setup({
      backend = "swi",
      run_on_save = false,
    })

    t.eq(swine._opts.backend, "swi")
    t.eq(swine._backend.id, "swi")
  end,
}
