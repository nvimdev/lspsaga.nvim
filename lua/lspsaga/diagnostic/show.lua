local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local util = require('lspsaga.util')
local diag = require('lspsaga.diagnostic')
local config = require('lspsaga').config
local beacon = require('lspsaga.beacon').jump_beacon
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

local function create_linked_list(entrys)
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

local function sort_entries(entrys)
  table.sort(entrys, function(a, b)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    elseif a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    else
      return a.col < b.col
    end
  end)
end

---single linked list
local function generate_list(entrys, callback)
  local diagnostic_config = vim.diagnostic.config and vim.diagnostic.config()
  local severity_sort_enabled = diagnostic_config and diagnostic_config.severity_sort

  if severity_sort_enabled then
    vim.defer_fn(function()
      sort_entries(entrys)
      local list = create_linked_list(entrys)
      if callback then
        callback(list)
      end
    end, 0)
  else
    local list = create_linked_list(entrys)
    if callback then
      callback(list)
    end
  end
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

function sd:layout_normal()
  self.bufnr, self.winid = win
    :new_normal('sp', self.bufnr)
    :bufopt({
      ['modifiable'] = false,
      ['filetype'] = 'sagadiagnostic',
      ['expandtab'] = false,
      ['bufhidden'] = 'wipe',
      ['buftype'] = 'nofile',
    })
    :winopt({
      ['number'] = false,
      ['relativenumber'] = false,
      ['stc'] = '',
      ['wrap'] = diag_conf.wrap_long_lines,
    })
    :wininfo()
  api.nvim_win_set_height(self.winid, 10)
end

function sd:layout_float(opt)
  --ensure close float win
  util.close_win(self.winid)
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
  if vim.tbl_contains(opt.args, '++unfocus') then
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
      ['buftype'] = 'nofile',
    })
    :winopt({
      ['conceallevel'] = 2,
      ['concealcursor'] = 'niv',
      ['wrap'] = diag_conf.wrap_long_lines,
    })
    :winhl('DiagnosticShowNormal', 'DiagnosticShowBorder')
    :wininfo()

  api.nvim_win_set_cursor(self.winid, { 2, 3 })
  for _, key in ipairs(diag_conf.keys.quit_in_show) do
    util.map_keys(self.bufnr, key, function()
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
        clean_ctx()
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
    .. entry.lnum + 1
    .. ':'
    .. entry.col + 1
    .. ':'
    .. entry.bufnr
    .. ' '
    .. (entry.source and entry.source or '')
    .. ' '
    .. (entry.code and entry.code or '')
end

function sd:toggle_or_jump(entrys_list)
  local lnum = api.nvim_win_get_cursor(0)[1]
  local node = find_node(entrys_list, lnum)
  if not node then
    local line = api.nvim_get_current_line()
    local info = line:match('%s(%d+:%d+:%d+)')
    if not info then
      return
    end
    api.nvim_win_close(self.winid, true)
    local ln, col, bn = unpack(vim.split(info, ':'))
    local wins = fn.win_findbuf(tonumber(bn))
    if #wins == 0 then
      ---@diagnostic disable-next-line: param-type-mismatch
      api.nvim_win_set_buf(0, tonumber(bn))
      wins[#wins] = 0
    end
    api.nvim_win_set_cursor(wins[#wins], { tonumber(ln), tonumber(col) - 1 })
    beacon({ tonumber(ln) - 1, 0 }, #api.nvim_get_current_line())
    clean_ctx()
    return
  end

  vim.bo[self.bufnr].modifiable = true
  if node.expand == true then
    api.nvim_buf_clear_namespace(self.bufnr, ns, lnum - 1, lnum + #node.diags)
    nvim_buf_set_lines(self.bufnr, lnum, lnum + #node.diags, false, {})
    node.expand = false
    nvim_buf_set_extmark(self.bufnr, ns, lnum - 1, 0, {
      virt_text = { { ui.expand, 'SagaToggle' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
    range_node_winline(node.next, -#node.diags)
    vim.bo[self.bufnr].modifiable = false
    return
  end

  if node.expand == false then
    nvim_buf_set_extmark(self.bufnr, ns, lnum - 1, 0, {
      virt_text = { { ui.collapse, 'SagaToggle' } },
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

      if i == 1 then
        ---@diagnostic disable-next-line: param-type-mismatch
        local fname = fn.fnamemodify(api.nvim_buf_get_name(tonumber(entry.bufnr)), ':t')
        local text = '  ' .. fname
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

      local messages = vim.split(entry.message, '\n')
      for j, message in ipairs(messages) do
        local mes = ''
        if j == 1 then
          mes = msg_fmt({
            message = message,
            lnum = entry.lnum,
            col = entry.col,
            bufnr = entry.bufnr,
            source = entry.source,
            code = entry.code,
          })
        else
          mes = ' ' .. message
        end

        self:write_line(mes, entry.severity, virt_start, count)
        count = count + 1
      end
    end
    curnode = curnode.next
  end

  local layout = diag_conf.show_layout
  opt.args = opt.args or {}
  if vim.tbl_contains(opt.args, '++float') then
    layout = 'float'
  elseif vim.tbl_contains(opt.args, '++normal') then
    layout = 'normal'
  end

  if layout == 'float' then
    self:layout_float(opt)
  else
    self:layout_normal()
  end

  api.nvim_win_set_cursor(self.winid, { 2, 3 })
  util.map_keys(self.bufnr, diag_conf.keys.toggle_or_jump, function()
    self:toggle_or_jump(opt.entrys_list)
  end)
end

function sd:show_diagnostics(opt)
  local has_jump_win = require('lspsaga.diagnostic').winid
  if has_jump_win and api.nvim_win_is_valid(has_jump_win) then
    return
  end

  local entrys = diag:get_diagnostic(opt)
  if next(entrys) == nil then
    return
  end

  generate_list(entrys, function(sorted_list)
    opt.entrys_list = sorted_list
    self:show(opt)
  end)
end

return setmetatable(ctx, sd)
