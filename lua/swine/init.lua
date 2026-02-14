local M = {}

local ns_diag = vim.api.nvim_create_namespace("swine_diag")
local ns_virt = vim.api.nvim_create_namespace("swine_virt")
local ns_qres = vim.api.nvim_create_namespace("swine_qres")

local aug_run = vim.api.nvim_create_augroup("SwineNvimRun", { clear = true })
local aug_hl = vim.api.nvim_create_augroup("SwineNvimHl", { clear = true })

local state = {}
local warned_auto_bg = false

local MIN_TIMEOUT_MS = 100
local MAX_TIMEOUT_MS = 600000

local DEFAULT_HL = {
  error = "DiagnosticVirtualTextError",
  warn = "DiagnosticVirtualTextWarn",
  hint = "DiagnosticVirtualTextHint",
  info = "DiagnosticVirtualTextInfo",
}

local CUSTOM_HL = {
  error = "SwineVirtError",
  warn = "SwineVirtWarn",
  hint = "SwineVirtHint",
  info = "SwineVirtInfo",
}

local HL_ATTR_KEYS = {
  "fg",
  "bg",
  "sp",
  "bold",
  "italic",
  "reverse",
  "standout",
  "underline",
  "undercurl",
  "underdouble",
  "underdotted",
  "underdashed",
  "strikethrough",
  "nocombine",
  "blend",
}

M._opts = {
  pattern = "*.pl",
  run_on_save = false,
  max_solutions = 50,
  load_timeout_ms = 4000,
  query_timeout_ms = 4000,
  virt_lines_bg = "auto",
  virt_lines_hl = nil,
  virt_lines_overflow = "scroll",
  virt_lines_leftcol = true,
  virt_lines_bar = "▌",
  virt_lines_pad = true,
  virt_lines_pad_extra = 1,
}

M._hl = {}

local diag_parser = require("swine.diag_parser")
local query_markers = require("swine.query_markers")
local query_output = require("swine.query_output")

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function hl(kind)
  return M._hl[kind] or DEFAULT_HL[kind] or "Normal"
end

local function pad_virtual_text(text, target_width)
  if not M._opts.virt_lines_pad then
    return text
  end

  local width = vim.fn.strdisplaywidth(text)
  local target = target_width or width
  local pad = math.max(0, target + M._opts.virt_lines_pad_extra - width)
  return text .. string.rep(" ", pad)
end

local function make_virt_line(text, kind, target_width)
  local group = hl(kind)
  local body = pad_virtual_text(text, target_width)
  local bar = M._opts.virt_lines_bar

  if type(bar) == "string" and bar ~= "" then
    return {
      { bar .. " ", group },
      { body, group },
    }
  end

  return {
    { body, group },
  }
end

local function virt_mark_opts(lines)
  return {
    virt_lines = lines,
    virt_lines_above = false,
    virt_lines_leftcol = M._opts.virt_lines_leftcol,
    virt_lines_overflow = M._opts.virt_lines_overflow,
  }
end

local function get_buf_state(buf)
  local s = state[buf]
  if not s then
    s = {
      seq = 0,
      status_mark = nil,
      diag_marks = {},
      query_marks = {},
    }
    state[buf] = s
    return s
  end

  s.diag_marks = s.diag_marks or {}
  s.query_marks = s.query_marks or {}
  return s
end

local function del_mark(buf, ns, id)
  if not id then
    return
  end

  pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
end

local function upsert_mark(buf, ns, id, lnum, col, opts)
  local payload = vim.deepcopy(opts)
  if id then
    payload.id = id
  end

  local ok, new_id = pcall(
    vim.api.nvim_buf_set_extmark,
    buf,
    ns,
    lnum,
    col,
    payload
  )
  if ok then
    return new_id
  end

  if id then
    payload.id = nil
    ok, new_id = pcall(
      vim.api.nvim_buf_set_extmark,
      buf,
      ns,
      lnum,
      col,
      payload
    )
    if ok then
      return new_id
    end
  end

  return nil
end

local function clear_query_marks(buf, s)
  for lnum, id in pairs(s.query_marks) do
    del_mark(buf, ns_qres, id)
    s.query_marks[lnum] = nil
  end
end

local function clear_buf(buf)
  local s = get_buf_state(buf)

  vim.diagnostic.reset(ns_diag, buf)
  vim.api.nvim_buf_clear_namespace(buf, ns_virt, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, ns_qres, 0, -1)

  s.status_mark = nil
  s.diag_marks = {}
  s.query_marks = {}
end

local function parse_diags(file, text)
  return diag_parser.parse(file, text, "swipl")
end

local function render_diags(buf, diags, s)
  vim.diagnostic.set(ns_diag, buf, diags, {
    virtual_text = false,
    signs = true,
    underline = true,
    update_in_insert = false,
  })

  local next_marks = {}
  local seen = {}

  for _, d in ipairs(diags) do
    local kind = (d.severity == vim.diagnostic.severity.ERROR)
      and "error" or "warn"

    local base = table.concat({
      tostring(d.lnum),
      tostring(d.col or 0),
      tostring(d.severity or 0),
      d.message or "",
    }, "|")

    seen[base] = (seen[base] or 0) + 1
    local key = base .. "#" .. tostring(seen[base])
    local mark_id = upsert_mark(
      buf,
      ns_virt,
      s.diag_marks[key],
      d.lnum,
      0,
      virt_mark_opts({ make_virt_line("↳ " .. d.message, kind) })
    )

    if mark_id then
      next_marks[key] = mark_id
    end
  end

  for key, mark_id in pairs(s.diag_marks) do
    if not next_marks[key] then
      del_mark(buf, ns_virt, mark_id)
    end
  end

  s.diag_marks = next_marks
end

local function collect_queries(buf, opts)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return query_markers.collect_from_lines(lines, opts.max_solutions)
end

local function run_cmd(cmd, timeout_ms, cb)
  vim.system(cmd, {
    text = true,
    timeout = timeout_ms,
  }, function(obj)
    vim.schedule(function()
      cb(obj)
    end)
  end)
end

local function is_timeout_result(obj, text)
  return query_output.is_timeout_result(obj, text)
end

local function set_status(buf, msg, kind, s)
  s.status_mark = upsert_mark(
    buf,
    ns_qres,
    s.status_mark,
    0,
    0,
    virt_mark_opts({ make_virt_line(msg, kind) })
  )
end

local function build_query_goal(max_solutions)
  return string.format(table.concat({
    "current_prolog_flag(argv,Argv),",
    "(Argv=[QAtom|_]->true;QAtom=''),",
    "catch((",
    "read_term_from_atom(QAtom,Q,[variable_names(VNs)]),",
    "findnsols(%d,VNs,Q,Sols),",
    "(Sols==[]->writeln('PLNB_FALSE');",
    "forall(nth1(I,Sols,SVNs),",
    "(SVNs==[]->format('PLNB_SOL ~d true~n',[I]);",
    "format('PLNB_SOL ~d ~q~n',[I,SVNs]))))",
    "),E,format('PLNB_ERROR ~q~n',[E]))",
  }), max_solutions)
end

local function parse_query_output(text, obj, timeout_ms)
  return query_output.parse(text, obj, timeout_ms)
end

local function line_end_col(buf, lnum)
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ""
  return #line
end

local function render_query_result(buf, lnum, rows, s)
  local text_rows = {}
  local max_width = 0

  for i, row in ipairs(rows) do
    local prefix = (i == 1) and "⇒ " or "  "
    local text = prefix .. row.text
    local width = vim.fn.strdisplaywidth(text)

    table.insert(text_rows, {
      text = text,
      kind = row.kind,
    })

    if width > max_width then
      max_width = width
    end
  end

  local virt_lines = {}
  for _, row in ipairs(text_rows) do
    table.insert(virt_lines, make_virt_line(row.text, row.kind, max_width))
  end

  local end_col = line_end_col(buf, lnum)
  local mark_opts = virt_mark_opts(virt_lines)
  mark_opts.right_gravity = true

  s.query_marks[lnum] = upsert_mark(
    buf,
    ns_qres,
    s.query_marks[lnum],
    lnum,
    end_col,
    mark_opts
  )
end

local function run_queries(buf, file, seq, s)
  local opts = M._opts
  local qs = collect_queries(buf, opts)
  local keep = {}

  for _, item in ipairs(qs) do
    keep[item.lnum] = true
  end

  for lnum, id in pairs(s.query_marks) do
    if not keep[lnum] then
      del_mark(buf, ns_qres, id)
      s.query_marks[lnum] = nil
    end
  end

  if #qs == 0 then
    local hint = "✓ loaded (no %?/%??/%N? queries)"
    set_status(buf, hint, "hint", s)
    return
  end

  set_status(
    buf,
    string.format("✓ loaded; running %d queries", #qs),
    "hint",
    s
  )

  for _, item in ipairs(qs) do
    local cmd = {
      "swipl",
      "-q",
      "-f",
      "none",
      "-l",
      file,
      "-g",
      build_query_goal(item.max_solutions),
      "-t",
      "halt",
      "--",
      item.query,
    }

    run_cmd(cmd, opts.query_timeout_ms, function(obj)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if not state[buf] or state[buf].seq ~= seq then
        return
      end

      local text = (obj.stdout or "") .. "\n" .. (obj.stderr or "")
      local rows = parse_query_output(text, obj, opts.query_timeout_ms)
      render_query_result(buf, item.lnum, rows, s)
    end)
  end
end

local function has_error(diags)
  for _, d in ipairs(diags) do
    if d.severity == vim.diagnostic.severity.ERROR then
      return true
    end
  end

  return false
end

local function run_for_buf(buf)
  local opts = M._opts

  if vim.fn.exepath("swipl") == "" then
    vim.notify("swipl not found in PATH", vim.log.levels.ERROR)
    return
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if vim.bo[buf].buftype ~= "" then
    return
  end

  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return
  end

  file = vim.fs.normalize(file)

  local s = get_buf_state(buf)
  s.seq = s.seq + 1
  local seq = s.seq

  set_status(buf, "… loading", "info", s)

  local cmd = {
    "swipl",
    "-q",
    "-f",
    "none",
    "-l",
    file,
    "-g",
    "halt",
  }

  run_cmd(cmd, opts.load_timeout_ms, function(obj)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    if not state[buf] or state[buf].seq ~= seq then
      return
    end

    local text = (obj.stdout or "") .. "\n" .. (obj.stderr or "")
    local diags = parse_diags(file, text)

    render_diags(buf, diags, s)

    if has_error(diags) then
      clear_query_marks(buf, s)
      set_status(buf, "✗ load failed; query eval skipped", "error", s)
      return
    end

    if is_timeout_result(obj, text) then
      clear_query_marks(buf, s)
      local msg = string.format("✗ load timeout after %d ms", opts.load_timeout_ms)
      set_status(buf, msg, "error", s)
      return
    end

    run_queries(buf, file, seq, s)
  end)
end

local function configure_autocmd()
  vim.api.nvim_clear_autocmds({ group = aug_run })

  if not M._opts.run_on_save then
    return
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug_run,
    pattern = M._opts.pattern,
    callback = function(a)
      run_for_buf(a.buf)
    end,
  })
end

local function get_hl_attrs(name)
  local ok, raw = pcall(vim.api.nvim_get_hl, 0, {
    name = name,
    link = false,
  })
  if not ok or type(raw) ~= "table" then
    return nil
  end

  local attrs = {}
  for _, key in ipairs(HL_ATTR_KEYS) do
    if raw[key] ~= nil then
      attrs[key] = raw[key]
    end
  end

  return attrs
end

local function blend_channel(src, dst, alpha)
  return math.floor(src + ((dst - src) * alpha) + 0.5)
end

local function adjust_bg_auto(base)
  if type(base) ~= "number" then
    return nil
  end

  local r = math.floor(base / 0x10000) % 0x100
  local g = math.floor(base / 0x100) % 0x100
  local b = base % 0x100

  local luma = (0.299 * r) + (0.587 * g) + (0.114 * b)
  local dark = luma < 128
  local dst = dark and 255 or 0
  local alpha = dark and 0.14 or 0.08

  local rr = blend_channel(r, dst, alpha)
  local gg = blend_channel(g, dst, alpha)
  local bb = blend_channel(b, dst, alpha)

  return (rr * 0x10000) + (gg * 0x100) + bb
end

local function derive_auto_bg()
  for _, group in ipairs({ "Normal", "NormalNC", "NormalFloat" }) do
    local attrs = get_hl_attrs(group)
    if attrs and attrs.bg then
      return adjust_bg_auto(attrs.bg)
    end
  end

  return nil
end

local function resolve_bg_value(bg_opt)
  if bg_opt == nil then
    return nil
  end

  if bg_opt == "auto" then
    local bg = derive_auto_bg()
    if not bg and not warned_auto_bg then
      warned_auto_bg = true
      vim.notify(
        "swine.nvim: could not derive auto background; using defaults",
        vim.log.levels.WARN
      )
    end
    return bg
  end

  return bg_opt
end

local function configure_highlights()
  M._hl = {}

  local bg = resolve_bg_value(M._opts.virt_lines_bg)
  local links = M._opts.virt_lines_hl

  if not bg and not links then
    return
  end

  for kind, default_group in pairs(DEFAULT_HL) do
    local source_group = default_group
    if links then
      source_group = links[kind] or links.all or source_group
    end

    local group = CUSTOM_HL[kind]
    if not bg then
      vim.api.nvim_set_hl(0, group, { link = source_group })
      M._hl[kind] = group
      goto continue
    end

    local attrs = get_hl_attrs(source_group) or {}
    attrs.bg = bg
    attrs.link = nil

    vim.api.nvim_set_hl(0, group, attrs)
    M._hl[kind] = group

    ::continue::
  end
end

local function configure_highlight_autocmd()
  vim.api.nvim_clear_autocmds({ group = aug_hl })

  if not M._opts.virt_lines_bg and not M._opts.virt_lines_hl then
    return
  end

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = aug_hl,
    callback = function()
      configure_highlights()
    end,
  })
end

local function define_user_command(name, fn, opts)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

local function cmd_run(args)
  local b = args.args ~= "" and tonumber(args.args)
    or vim.api.nvim_get_current_buf()
  run_for_buf(b)
end

local function cmd_clear(args)
  local b = args.args ~= "" and tonumber(args.args)
    or vim.api.nvim_get_current_buf()
  clear_buf(b)
end

local function cmd_toggle_auto()
  M._opts.run_on_save = not M._opts.run_on_save
  configure_autocmd()

  local status = M._opts.run_on_save and "enabled" or "disabled"
  vim.notify("swine.nvim run-on-save " .. status)
end

local function parse_virt_lines_hl(raw)
  if raw == nil then
    return nil
  end

  if type(raw) == "string" and raw ~= "" then
    return { all = raw }
  end

  if type(raw) ~= "table" then
    vim.notify(
      "swine.nvim: virt_lines_hl must be string, table, or nil",
      vim.log.levels.WARN
    )
    return nil
  end

  local out = {}
  if type(raw.all) == "string" and raw.all ~= "" then
    out.all = raw.all
  end

  for kind, _ in pairs(DEFAULT_HL) do
    local v = raw[kind]
    if type(v) == "string" and v ~= "" then
      out[kind] = v
    end
  end

  return next(out) and out or nil
end

local function parse_virt_lines_overflow(raw)
  if raw == nil then
    return "scroll"
  end

  if raw == "scroll" or raw == "trunc" then
    return raw
  end

  vim.notify(
    "swine.nvim: virt_lines_overflow must be 'scroll' or 'trunc'",
    vim.log.levels.WARN
  )
  return "scroll"
end

local function parse_virt_lines_leftcol(raw)
  if raw == nil then
    return true
  end

  if type(raw) == "boolean" then
    return raw
  end

  vim.notify(
    "swine.nvim: virt_lines_leftcol must be boolean",
    vim.log.levels.WARN
  )
  return true
end

local function parse_virt_lines_bar(raw)
  if raw == nil then
    return "▌"
  end

  if type(raw) == "string" then
    return raw
  end

  vim.notify("swine.nvim: virt_lines_bar must be a string", vim.log.levels.WARN)
  return "▌"
end

local function parse_virt_lines_pad(raw)
  if raw == nil then
    return true
  end

  if type(raw) == "boolean" then
    return raw
  end

  vim.notify("swine.nvim: virt_lines_pad must be boolean", vim.log.levels.WARN)
  return true
end

local function parse_virt_lines_pad_extra(raw)
  if raw == nil then
    return 1
  end

  if type(raw) ~= "number" then
    vim.notify(
      "swine.nvim: virt_lines_pad_extra must be a number",
      vim.log.levels.WARN
    )
    return 1
  end

  return clamp(math.floor(raw), 0, 16)
end

function M.setup(opts)
  opts = opts or {}

  local virt_lines_bg = opts.virt_lines_bg
  if virt_lines_bg == nil then
    virt_lines_bg = "auto"
  end

  if type(virt_lines_bg) ~= "string"
    and type(virt_lines_bg) ~= "number"
    and virt_lines_bg ~= nil
  then
    vim.notify(
      "swine.nvim: virt_lines_bg must be string, number, or nil",
      vim.log.levels.WARN
    )
    virt_lines_bg = "auto"
  end

  M._opts = {
    pattern = opts.pattern or "*.pl",
    run_on_save = opts.run_on_save == true,
    max_solutions = clamp(opts.max_solutions or 50, 1, 500),
    load_timeout_ms = clamp(
      opts.load_timeout_ms or 4000,
      MIN_TIMEOUT_MS,
      MAX_TIMEOUT_MS
    ),
    query_timeout_ms = clamp(
      opts.query_timeout_ms or 4000,
      MIN_TIMEOUT_MS,
      MAX_TIMEOUT_MS
    ),
    virt_lines_bg = virt_lines_bg,
    virt_lines_hl = parse_virt_lines_hl(opts.virt_lines_hl),
    virt_lines_overflow = parse_virt_lines_overflow(opts.virt_lines_overflow),
    virt_lines_leftcol = parse_virt_lines_leftcol(opts.virt_lines_leftcol),
    virt_lines_bar = parse_virt_lines_bar(opts.virt_lines_bar),
    virt_lines_pad = parse_virt_lines_pad(opts.virt_lines_pad),
    virt_lines_pad_extra = parse_virt_lines_pad_extra(opts.virt_lines_pad_extra),
  }

  configure_highlights()
  configure_highlight_autocmd()

  define_user_command("SwineRun", cmd_run, { nargs = "?" })
  define_user_command("SwineClear", cmd_clear, { nargs = "?" })
  define_user_command("SwineToggleAuto", cmd_toggle_auto, {})

  configure_autocmd()
end

M.run = run_for_buf
M.clear = clear_buf

return M
