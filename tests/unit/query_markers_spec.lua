local query_markers = require("swine.query_markers")

return {
  ["parses %? markers"] = function(t)
    local q, n = query_markers.parse("%? member(X, [a,b]).", 50)
    t.eq(q, "member(X, [a,b])")
    t.eq(n, 1)
  end,

  ["parses %?? markers and clamps to max"] = function(t)
    local q, n = query_markers.parse("%??? member(X, [a,b,c]).", 2)
    t.eq(q, "member(X, [a,b,c])")
    t.eq(n, 2)
  end,

  ["parses %N? markers"] = function(t)
    local q, n = query_markers.parse("%10? between(1, 20, N).", 50)
    t.eq(q, "between(1, 20, N)")
    t.eq(n, 10)
  end,

  ["ignores invalid markers"] = function(t)
    local q, n = query_markers.parse("%?", 50)
    t.is_nil(q)
    t.is_nil(n)
  end,

  ["collects markers from lines"] = function(t)
    local rows = query_markers.collect_from_lines({
      "%? true.",
      "foo.",
      "%3? member(X, [a,b,c]).",
    }, 50)

    t.eq(rows, {
      { lnum = 0, query = "true", max_solutions = 1 },
      { lnum = 2, query = "member(X, [a,b,c])", max_solutions = 3 },
    })
  end,

  ["collects multiline markers with %| continuation"] = function(t)
    local rows = query_markers.collect_from_lines({
      "%? member(X, [a,b,c]),",
      "%| X \\= b,",
      "%| writeln(X).",
    }, 50)

    t.eq(rows, {
      {
        lnum = 2,
        query = table.concat({
          "member(X, [a,b,c]),",
          "X \\= b,",
          "writeln(X)",
        }, "\n"),
        max_solutions = 1,
      },
    })
  end,

  ["allows blank %| continuation lines"] = function(t)
    local rows = query_markers.collect_from_lines({
      "%? member(X, [a,b,c]),",
      "%|",
      "%| X \\= b.",
    }, 50)

    t.eq(rows, {
      {
        lnum = 2,
        query = table.concat({
          "member(X, [a,b,c]),",
          "",
          "X \\= b",
        }, "\n"),
        max_solutions = 1,
      },
    })
  end,

  ["allows %? line with continuation-only query"] = function(t)
    local rows = query_markers.collect_from_lines({
      "%?",
      "%| true.",
    }, 50)

    t.eq(rows, {
      { lnum = 1, query = "true", max_solutions = 1 },
    })
  end,

  ["ignores orphan %| continuation line"] = function(t)
    local rows = query_markers.collect_from_lines({
      "%| true.",
    }, 50)

    t.eq(rows, {})
  end,
}
