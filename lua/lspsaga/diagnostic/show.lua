local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local util = require('lspsaga.util')
local diag = require('lspsaga.diagnostic')
local config = require('lspsaga').config
local ui = config.ui
local diag_conf = config.diagnostic
local ns = api.nvim_create_namespace('SagaDiagnostic')
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local nvim_buf_add_highlight = api.nvim_buf_add_highlight
local nvim_buf_set_lines = api.nvim_buf_set_lines
local ctx = {}
local sd = {}
sd.__index = sd

function sd.__newindex(t, k, v)
  rawset(t, k, v)
end

--- clean ctx
local function clean_ctx()
  for i, _ in pairs(ctx) do
    ctx[i] = nil
  end
end

local function new_node()
  return {
    next = nil,
    diags = {},
    expand = false,
    lnum = 0,
  }
end

---single linked list
local function generate_list(entrys)
  local list = new_node()

  local curnode
  for _, item in ipairs(entrys) do
    if #list.diags == 0 then
      curnode = list
    elseif item.bufnr ~= curnode.diags[#curnode.diags].bufnr then
      if not curnode.next then
        curnode.next = new_node()
      end
      curnode = curnode.next
    end
    curnode.diags[#curnode.diags + 1] = item
  end
  return list
end

local function find_node(list, lnum)
  local curnode = list
  while curnode do
    if curnode.lnum == lnum then
      return curnode
    end
    curnode = curnode.next
  end
end

local function range_node_winline(node, val)
  while node do
    node.lnum = node.lnum + val
    node = node.next
  end
end

function sd:create_win(opt)
  local curbuf = api.nvim_get_current_buf()
  local content = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local increase = util.win_height_increase(content)
  local max_len = util.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * diag_conf.max_show_height)
  local max_width = math.floor(vim.o.columns * diag_conf.max_show_width)
  local float_opt = {
    width = math.min(max_width, max_len),
    height = math.min(max_height, #content + increase),
    bufnr = self.bufnr,
  }
  local enter = true

  if ui.title then
    if opt.buffer then
      float_opt.title = 'Buffer'
    elseif opt.line then
      float_opt.title = 'Line'
    elseif opt.cursor then
      float_opt.title = 'Cursor'
    else
      float_opt.title = 'Workspace'
    end
    float_opt.title_pos = 'center'
  end

  local close_autocmds =
    { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufDelete', 'WinScrolled' }
  if opt.arg and opt.arg == '++unfocus' then
    opt.focusable = false
    close_autocmds[#close_autocmds] = 'BufLeave'
    enter = false
  else
    opt.focusable = true
    api.nvim_create_autocmd('BufEnter', {
      callback = function(args)
        if not self.winid or not api.nvim_win_is_valid(self.winid) then
          pcall(api.nvim_del_autocmd, args.id)
        end
        local cur_buf = api.nvim_get_current_buf()
        if cur_buf ~= self.bufnr and self.winid and api.nvim_win_is_valid(self.winid) then
          api.nvim_win_close(self.winid, true)
          clean_ctx()
          pcall(api.nvim_del_autocmd, args.id)
        end
      end,
    })
  end

  self.bufnr, self.winid = win
    :new_float(float_opt, enter)
    :bufopt({
      ['filetype'] = 'markdown',
      ['modifiable'] = false,
    })
    :winopt({
      ['conceallevel'] = 2,
      ['concealcursor'] = 'niv',
      ['winhl'] = 'NormalFloat:DiagnosticShowNormal,Border:DiagnosticShowBorder',
    })
    :wininfo()

  api.nvim_win_set_cursor(self.winid, { 2, 3 })
  for _, key in ipairs(diag_conf.keys.quit_in_show) do
    util.map_keys(self.bufnr, 'n', key, function()
      local curwin = api.nvim_get_current_win()
      if curwin ~= self.winid then
        return
      end
      if api.nvim_win_is_valid(curwin) then
        api.nvim_win_close(curwin, true)
        clean_ctx()
      end
    end)
  end

  vim.defer_fn(function()
    api.nvim_create_autocmd(close_autocmds, {
      buffer = curbuf,
      once = true,
      callback = function(args)
        if self.winid and api.nvim_win_is_valid(self.winid) then
          api.nvim_win_close(self.winid, true)
        end
        api.nvim_del_autocmd(args.id)
      end,
    })
  end, 0)
end

function sd:write_line(message, severity, virt_line, srow, erow)
  local indent = (' '):rep(3)
  srow = srow or -1
  erow = erow or -1
  if message:find('\n') then
    message = vim.split(message, '\n')
    message = table.concat(message)
  end

  nvim_buf_set_lines(self.bufnr, srow, erow, false, { indent .. message })
  nvim_buf_add_highlight(
    self.bufnr,
    0,
    'Diagnostic' .. vim.diagnostic.severity[severity],
    srow,
    0,
    -1
  )
  nvim_buf_set_extmark(self.bufnr, ns, srow, 0, {
    virt_text = {
      { virt_line, 'SagaVirtLine' },
      { ui.lines[4], 'SagaVirtLine' },
      { ui.lines[4], 'SagaVirtLine' },
    },
    virt_text_pos = 'overlay',
    hl_mode = 'combine',
  })
end

local function msg_fmt(entry)
  return entry.message
    .. ' '
    .. entry.lnum
    .. ':'
    .. entry.col
    .. ':'
    .. entry.bufnr
    .. ' '
    .. (entry.source and entry.source or '')
    .. (entry.code and entry.code or '')
end

function sd:toggle_expand(entrys_list)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local node = find_node(entrys_list, lnum)
  if not node then
    local line = api.nvim_get_current_line()
    local info = line:match('%s(%d+:%d+:%d+)')
    if not info then
      return
    end
    local ln, col, bn = unpack(vim.split(info, ':'))
    local wins = fn.win_findbuf(tonumber(bn))
    api.nvim_win_set_cursor(wins[#wins], { tonumber(ln) + 1, tonumber(col) })
    return
  end

  vim.bo[self.bufnr].modifiable = true
  if node.expand then
    api.nvim_buf_clear_namespace(self.bufnr, ns, lnum - 1, lnum + #node.diags)
    nvim_buf_set_lines(self.bufnr, lnum, lnum + #node.diags, false, {})
    node.expand = false
    nvim_buf_set_extmark(self.bufnr, ns, lnum - 1, 0, {
      virt_text = { { ui.expand, 'SagaExpand' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
    range_node_winline(node.next, -#node.diags)
  else
    nvim_buf_set_extmark(self.bufnr, ns, lnum - 1, 0, {
      virt_text = { { ui.collapse, 'SagaCollapse' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
    for i, item in ipairs(node.diags) do
      local mes = msg_fmt(item)
      local virt_start = i == #node.diags and ui.lines[1] or ui.lines[2]
      self:write_line(mes, item.severity, virt_start, lnum, lnum)
      lnum = lnum + 1
    end
    node.expand = true
    range_node_winline(node.next, #node.diags)
  end
  vim.bo[self.bufnr].modifiable = false
end

function sd:show(opt)
  self.bufnr = api.nvim_create_buf(false, false)
  local curnode = opt.entrys_list
  local count = 0
  while curnode do
    curnode.expand = true
    for i, entry in ipairs(curnode.diags) do
      local virt_start = i == #curnode.diags and ui.lines[1] or ui.lines[2]
      local mes = msg_fmt(entry)

      if i == 1 then
        ---@diagnostic disable-next-line: param-type-mismatch
        local fname = fn.fnamemodify(api.nvim_buf_get_name(tonumber(entry.bufnr)), ':t')
        -- local counts = diag:get_diag_counts(curnode.diags)
        local text = '  ' .. fname .. ' ' .. entry.bufnr
        nvim_buf_set_lines(self.bufnr, count, -1, false, { text })
        nvim_buf_set_extmark(self.bufnr, ns, count, 0, {
          virt_text = {
            { ui.collapse, 'SagaCollapse' },
          },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
        count = count + 1
        curnode.lnum = count
      end
      self:write_line(mes, entry.severity, virt_start, count)
      count = count + 1
    end
    curnode = curnode.next
  end

  self:create_win(opt)
  util.map_keys(self.bufnr, 'n', diag_conf.keys.toggle_or_jump, function()
    self:toggle_expand(opt.entrys_list)
  end)
end

function sd:show_diagnostics(opt)
  local entrys = diag:get_diagnostic(opt)
  if next(entrys) == nil then
    return
  end
  opt.entrys_list = generate_list(entrys)
  self:show(opt)
end

return setmetatable(ctx, sd)
