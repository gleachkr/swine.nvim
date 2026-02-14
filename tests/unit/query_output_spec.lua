local query_output = require("swine.query_output")

return {
  ["parses explicit query errors"] = function(t)
    local rows = query_output.parse("PLNB_ERROR error(foo)", { code = 0 }, 4000)
    t.eq(rows, {
      { text = "error: error(foo)", kind = "error" },
    })
  end,

  ["parses false"] = function(t)
    local rows = query_output.parse("PLNB_FALSE", { code = 0 }, 4000)
    t.eq(rows, {
      { text = "false", kind = "warn" },
    })
  end,

  ["parses one binding solution"] = function(t)
    local rows = query_output.parse("PLNB_SOL 1 ['X'=42]", { code = 0 }, 4000)
    t.eq(rows, {
      { text = "X = 42", kind = "hint" },
    })
  end,

  ["numbers multiple solutions"] = function(t)
    local text = table.concat({
      "PLNB_SOL 1 ['X'=a]",
      "PLNB_SOL 2 ['X'=b]",
    }, "\n")

    local rows = query_output.parse(text, { code = 0 }, 4000)
    t.eq(rows, {
      { text = "1) X = a", kind = "hint" },
      { text = "2) X = b", kind = "hint" },
    })
  end,

  ["reports timeout"] = function(t)
    local rows = query_output.parse("", { code = 124 }, 4000)
    t.eq(rows, {
      { text = "timeout after 4000 ms", kind = "error" },
    })
  end,

  ["reports non-zero process errors"] = function(t)
    local rows = query_output.parse("boom", { code = 2 }, 4000)
    t.eq(rows, {
      { text = "error (2): boom", kind = "error" },
    })
  end,
}
