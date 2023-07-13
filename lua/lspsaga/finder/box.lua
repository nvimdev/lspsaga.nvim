local vfn = vim.fn
local treesitter = vim.treesitter
local M = {}
---@diagnostic disable-next-line: deprecated
local api, uv = vim.api, vim.version().minor >= 10 and vim.uv or vim.loop
local win = require('lspsaga.window')
local config = require('lspsaga').config

function M.get_methods(args)
  local methods = {
    ['def'] = 'textDocument/definition',
    ['ref'] = 'textDocument/references',
    ['imp'] = 'textDocument/implementation',
  }
  methods = vim.tbl_extend('force', methods, config.finder.methods)
  local keys = vim.tbl_keys(methods)
  return vim.tbl_map(function(item)
    if vim.tbl_contains(keys, item) then
      return methods[item]
    end
  end, args)
end

function M.parse_argument(args)
  local methods = {}
  local layout
  for _, arg in ipairs(args) do
    if arg:find('^%w+$') then
      methods[#methods + 1] = arg
    elseif arg:find('%w+%+%w+') then
      methods = vim.split(arg, '+', { plain = true })
    elseif arg:find('%+%+normal') then
      layout = 'normal'
    elseif arg:find('%+%+float') then
      layout = 'float'
    end
  end
  return methods, layout
end

function M.filter(method, results)
  if vim.tbl_isempty(config.finder.filter) or not config.finder.filter[method] then
    return results
  end
  local fn = config.finder.filter[method]
  if type(fn) ~= 'function' then
    vim.notify('[Lspsaga] filter must be function', vim.log.levels.ERROR)
    return
  end
  local retval = {}
  for client_id, item in pairs(results) do
    retval[client_id] = {}
    for _, val in ipairs(item) do
      if fn(val) then
        retval[client_id][#retval[client_id] + 1] = val
      end
    end
  end
  return retval
end

function M.spinner()
  local timer = uv.new_timer()
  local bufnr, winid = win
    :new_float({
      width = 10,
      height = 1,
      border = 'solid',
      focusable = false,
      noautocmd = true,
    }, true)
    :bufopt({
      ['bufhidden'] = 'wipe',
      ['buftype'] = 'nofile',
    })
    :wininfo()

  local spinner = {
    '●∙∙∙∙∙∙∙∙',
    ' ●∙∙∙∙∙∙∙',
    '  ●∙∙∙∙∙∙',
    '   ●∙∙∙∙∙',
    '    ●∙∙∙∙',
    '     ●∙∙∙',
    '      ●∙∙',
    '       ●∙',
    '        ●',
  }
  local frame = 1

  timer:start(0, 50, function()
    vim.schedule(function()
      if not api.nvim_buf_is_valid(bufnr) then
        return
      end
      api.nvim_buf_set_lines(bufnr, 0, -1, false, { spinner[frame] })
      api.nvim_buf_add_highlight(bufnr, 0, 'SagaSpinner', 0, 0, -1)
      frame = frame + 1 > #spinner and 1 or frame + 1
    end)
  end)

  return function()
    if timer:is_active() and not timer:is_closing() then
      timer:stop()
      timer:close()
      api.nvim_win_close(winid, true)
    end
  end
end

local function to_normal_bg()
  local data = api.nvim_get_hl_by_name('SagaNormal', true)
  if data.background then
    return { fg = data.background }
  end
  return { link = 'SagaVirtLine' }
end

local function indent_range(inlevel)
  local curlnum = api.nvim_win_get_cursor(0)[1]
  local start, _end
  if inlevel > 4 then
    for i = curlnum - 1, 0, -1 do
      if vfn.indent(i) < inlevel or i == 0 then
        start = i
        break
      end
    end
  end

  local count = api.nvim_buf_line_count(0)
  for i = curlnum + 1, count, 1 do
    if inlevel == 6 and vfn.indent(i) < inlevel then
      _end = i
      break
    elseif inlevel == 4 and vfn.indent(i) <= inlevel then
      _end = i
      break
    end
  end
  _end = _end or count
  return { start and start - 1 or curlnum, _end - 1 }
end

function M.indent_current(inlevel)
  local current = inlevel - 2
  local range = indent_range(inlevel)
  local t = { 0, 2, 4 }

  for i = 0, api.nvim_buf_line_count(0) - 1 do
    vim.tbl_map(function(item)
      local hi = (item == current and i >= range[1] and i <= range[2]) and { link = 'Type' }
        or to_normal_bg()
      api.nvim_set_hl(0, 'SagaIndent' .. i .. item, hi)
    end, t)
  end
end

function M.indent(ns, lbufnr, lwinid)
  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, winid, bufnr)
      if winid ~= lwinid or lbufnr ~= bufnr then
        return false
      end
    end,
    on_start = function()
      if api.nvim_get_current_buf() ~= lbufnr then
        return false
      end
    end,
    on_line = function(_, winid, bufnr, row)
      local inlevel = vim.fn.indent(row + 1)
      if bufnr ~= lbufnr or winid ~= lwinid or inlevel == 2 then
        return
      end

      local total = inlevel == 4 and 4 - 2 or inlevel - 1
      local conf = to_normal_bg()

      for i = 1, total, 2 do
        local hi = 'SagaIndent' .. row .. (i - 1)
        api.nvim_buf_set_extmark(bufnr, ns, row, i - 1, {
          virt_text = { { config.ui.lines[3], hi } },
          virt_text_pos = 'overlay',
          ephemeral = true,
        })
        api.nvim_set_hl(0, hi, { link = 'SagaNormal', default = true })
      end
    end,
  })
end

function M.ts_highlight(bufnr)
  local lang = treesitter.language.get_lang(vim.bo[bufnr].filetype)
  local ok = pcall(treesitter.get_parser, bufnr, lang)
  if not ok then
    vim.bo[bufnr].syntax = 'on'
    return
  end
  treesitter.start(bufnr, lang)
end

return M
