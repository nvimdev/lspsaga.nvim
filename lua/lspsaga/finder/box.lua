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

function M.indent_current(inlevel)
  local available = { 0, 2, 4 }
  local current = inlevel - 2
  vim.tbl_map(function(index)
    local hi = index == current and 'Type' or 'Comment'
    api.nvim_set_hl(0, 'SagaIndent' .. index, { link = hi })
  end, available)
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

      for i = 1, total, 2 do
        api.nvim_buf_set_extmark(bufnr, ns, row, i - 1, {
          virt_text = { { config.ui.lines[3], 'SagaIndent' .. (i - 1) } },
          virt_text_pos = 'overlay',
          ephemeral = true,
        })
      end
    end,
  })
end

return M
