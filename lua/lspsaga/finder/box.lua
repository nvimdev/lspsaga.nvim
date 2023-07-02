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
  local methods, layout
  for _, arg in ipairs(args) do
    if arg:find('%w+%+%w+') then
      methods = vim.split(arg, '+', { plain = true })
    end
    if arg:find('%+%+') then
      layout = vim.split(arg, '%+%+')[1]
    end
  end
  return methods, layout
end

function M.filter(method, results)
  if vim.tbl_isempty(config.finder.filter) or not config.finder.filter[method] then
    return results
  end
  local fn = config.finder.filter[method]
  local retval = {}
  for client_id, item in pairs(results) do
    retval[client_id] = {
      result = fn(client_id, item.result),
    }
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
    }, false)
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

return M
