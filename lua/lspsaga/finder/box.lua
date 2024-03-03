local vfn = vim.fn
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
  local layout, inexist
  for _, arg in ipairs(args) do
    if arg:find('^%w+$') then
      methods[#methods + 1] = arg
    elseif arg:find('%w+%+%w+') then
      methods = vim.split(arg, '+', { plain = true })
    elseif arg:find('%+%+normal') then
      layout = 'normal'
    elseif arg:find('%+%+float') then
      layout = 'float'
    elseif arg:find('%+%+inexist') then
      inexist = true
    end
  end
  return methods, layout, inexist
end

function M.filter(method, results)
  if vim.tbl_isempty(config.finder.filter) or not config.finder.filter[method] then
    return results
  end
  local fn = config.finder.filter[method]
  if type(fn) ~= 'function' then
    vim.notify('[lspsaga] filter must be a function', vim.log.levels.ERROR)
    return
  end
  local retval = {}
  for client_id, item in pairs(results) do
    -- NOTE: by the example, fn(client_id, result) is supp to return a bool
    -- and if the results tbl = { { result = { {...}, {...}, ... } } }
    -- likely want to allow user to filter using the members of the result table
    -- rather than all the results
    for _, result_member in ipairs(item.result) do
      if fn(client_id, result_member) == true then
        if retval[client_id] == nil then
          retval[client_id] = { result = { result_member } }
        else
          table.insert(retval[client_id].result, result_member)
        end
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

local con_ns = api.nvim_create_namespace('FinderCurrent')
function M.indent_current(inlevel)
  local current = inlevel - 2
  local range = indent_range(inlevel)
  local t = { 0, 2, 4 }
  local currow = api.nvim_win_get_cursor(0)[1] - 1
  api.nvim_buf_clear_namespace(0, con_ns, 0, -1)
  if current == 4 then
    api.nvim_buf_set_extmark(0, con_ns, currow, current + 1, {
      virt_text = { { config.ui.lines[4], 'SagaInCurrent' } },
      virt_text_pos = 'overlay',
    })
  end

  for i = 0, api.nvim_buf_line_count(0) - 1 do
    vim.tbl_map(function(item)
      local hi = (item == current and i >= range[1] and i <= range[2])
          and { link = 'SagaInCurrent' }
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
      local currow = api.nvim_win_get_cursor(0)[1] - 1
      local inlevel = vim.fn.indent(row + 1)
      if bufnr ~= lbufnr or winid ~= lwinid or inlevel == 2 then
        return
      end
      local total = inlevel == 4 and 4 - 2 or inlevel - 1

      for i = 1, total, 2 do
        local hi = 'SagaIndent' .. row .. (i - 1)
        local virt = (row == currow and inlevel == 6 and i - 1 == 4) and config.ui.lines[2]
          or config.ui.lines[3]
        api.nvim_buf_set_extmark(bufnr, ns, row, i - 1, {
          virt_text = { { virt, hi } },
          virt_text_pos = 'overlay',
          ephemeral = true,
        })
        api.nvim_set_hl(0, hi, { link = 'SagaNormal', default = true })
      end
    end,
  })
end

function M.win_reuse(direction)
  local wins = api.nvim_tabpage_list_wins(0)
  if #wins == 1 then
    return
  end
  local curwin = api.nvim_get_current_win()
  local curwin_pos = vfn.win_screenpos(curwin)
  local winheight = api.nvim_win_get_height(curwin)
  local winwidth = api.nvim_win_get_width(curwin)
  local index
  if direction == 'vsplit' and winwidth ~= vim.o.columns then
    index = 2
  elseif direction == 'split' and winheight ~= vim.o.lines then
    index = 1
  end

  if not index then
    return
  end

  for _, winid in ipairs(wins) do
    if winid ~= curwin and vfn.win_screenpos(winid)[index] > curwin_pos[index] then
      return winid
    end
  end
end

return M
