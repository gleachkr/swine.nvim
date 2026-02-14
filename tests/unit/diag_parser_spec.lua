local diag_parser = require("swine.diag_parser")

return {
  ["parses load errors and warnings for one file"] = function(t)
    local file = vim.fs.normalize("/tmp/demo.pl")
    local other = vim.fs.normalize("/tmp/other.pl")

    local text = table.concat({
      "ERROR: " .. file .. ":3:4: Syntax error: Unexpected end of file",
      "ERROR: [Thread main] " .. file .. ":4:2: Token too long",
      "ERROR: " .. file .. ":5: Unknown procedure: foo/0",
      "Warning: " .. file .. ":7: Singleton variables: [X]",
      "ERROR: " .. other .. ":3: should be ignored",
    }, "\n")

    local diags = diag_parser.parse(file, text, "swipl")

    t.eq(diags, {
      {
        lnum = 2,
        col = 3,
        message = "Syntax error: Unexpected end of file",
        source = "swipl",
        severity = vim.diagnostic.severity.ERROR,
      },
      {
        lnum = 3,
        col = 1,
        message = "Token too long",
        source = "swipl",
        severity = vim.diagnostic.severity.ERROR,
      },
      {
        lnum = 4,
        col = 0,
        message = "Unknown procedure: foo/0",
        source = "swipl",
        severity = vim.diagnostic.severity.ERROR,
      },
      {
        lnum = 6,
        col = 0,
        message = "Singleton variables: [X]",
        source = "swipl",
        severity = vim.diagnostic.severity.WARN,
      },
    })
  end,
}
