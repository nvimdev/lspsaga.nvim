local ot = {}
local api, lsp, fn, keymap = vim.api, vim.lsp, vim.fn, vim.keymap
local config = require('lspsaga').config
local util = require('lspsaga.util')
local symbol = require('lspsaga.symbol')
local window = require('lspsaga.window')
local outline_conf = config.outline
local ctx = {}

function ot.__newindex(t, k, v)
  rawset(t, k, v)
end

ot.__index = ot

local function clean_ctx()
  if ctx.group then
    api.nvim_del_augroup_by_id(ctx.group)
  end
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

---@private
local function set_local()
  local local_options = {
    bufhidden = 'wipe',
    number = false,
    relativenumber = false,
    filetype = 'lspsagaoutline',
    buftype = 'nofile',
    wrap = false,
    signcolumn = 'no',
    matchpairs = '',
    buflisted = false,
    list = false,
    spell = false,
    cursorcolumn = false,
    cursorline = false,
    winfixwidth = true,
    winhl = 'Normal:OutlineNormal',
    stc = '',
  }
  for opt, val in pairs(local_options) do
    vim.opt_local[opt] = val
  end
end

local function get_hi_prefix()
  return 'SagaWinbar'
end

local function get_kind()
  return require('lspsaga.lspkind').get_kind()
end

local function find_node(data, line)
  for _, node in pairs(data or {}) do
    if node.winline == line then
      return node
    end
  end
end

---@private
local function create_outline_window()
  if #outline_conf.win_with > 0 then
    local ok, sp_buf = util.find_buffer_by_filetype(outline_conf.win_with)

    if ok then
      local winid = fn.win_findbuf(sp_buf)[1]
      api.nvim_set_current_win(winid)
      vim.cmd('sp vnew')
      return
    end
  end

  local pos = outline_conf.win_position == 'right' and 'botright' or 'topleft'
  vim.cmd(pos .. ' vnew')
  local winid, bufnr = api.nvim_get_current_win(), api.nvim_get_current_buf()
  set_local()
  api.nvim_win_set_width(winid, config.outline.win_width)
  return winid, bufnr
end

function ot:apply_map(symbol_data)
  local maps = outline_conf.keys
  local opt = { buffer = self.bufnr, nowait = true }
  keymap.set('n', maps.quit, function()
    if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) then
      api.nvim_buf_delete(self.bufnr, { force = true })
    end
    if self.winid and api.nvim_win_is_valid(self.winid) then
      api.nvim_win_close(self.winid, true)
    end
    clean_ctx()
  end, opt)

  local function open()
    local curline = api.nvim_win_get_cursor(0)[1]
    local node
    for _, nodes in pairs(symbol_data) do
      node = find_node(nodes.data, curline)
      if node then
        break
      end
    end

    if not node then
      return
    end
    local range = node.range and node.range or node.location.range

    local winid = fn.bufwinid(self.render_buf)
    api.nvim_set_current_win(winid)
    if node.pos then
      api.nvim_win_set_cursor(winid, { node.pos[1] + 1, node.pos[2] })
    else
      api.nvim_win_set_cursor(winid, { range.start.line + 1, range.start.character })
    end
    local width = #api.nvim_get_current_line()
    util.jump_beacon({ range.start.line, range.start.character }, width)
    if outline_conf.close_after_jump then
      self:close_and_clean()
    end
  end

  keymap.set('n', maps.expand_or_jump, function()
    local text = api.nvim_get_current_line()
    if text:find(config.ui.expand) or text:find(config.ui.collapse) then
      self:expand_collapse(symbol_data)
      return
    end
    open()
  end, opt)
end

function ot:request_and_render(buf)
  local params = { textDocument = lsp.util.make_text_document_params(buf) }
  local client = util.get_client_by_cap('documentSymbolProvider')
  if not client then
    return
  end

  client.request('textDocument/documentSymbol', params, function(_, result)
    self.pending_request = false
    if not result or next(result) == nil then
      return
    end
  end, buf)
end

function ot:expand_collapse(symbol_data)
  local curline = api.nvim_win_get_cursor(0)[1]
  local node = find_node(symbol_data, curline)
  if not node then
    return
  end
  local prefix = get_hi_prefix()
  local kind = get_kind()

  local function increase_or_reduce(lnum, num)
    for k, v in pairs(symbol_data) do
      if v.winline > lnum then
        symbol_data[k].winline = symbol_data[k].winline + num
        for _, item in pairs(v.data) do
          item.winline = item.winline + num
        end
      end
    end
  end

  if node.expand then
    local text = api.nvim_get_current_line()
    text = text:gsub(config.ui.collapse, config.ui.expand)
    for _, v in ipairs(node.data) do
      v.winline = -1
    end
    vim.bo[self.bufnr].modifiable = true
    api.nvim_buf_set_lines(self.bufnr, curline - 1, curline + #node.data, false, { text })
    vim.bo[self.bufnr].modifiable = false
    node.expand = false
    api.nvim_buf_add_highlight(self.bufnr, 0, 'SagaCollapse', curline - 1, 0, 5)
    api.nvim_buf_add_highlight(
      self.bufnr,
      0,
      prefix .. kind[node.data[1].kind][1],
      curline - 1,
      5,
      -1
    )
    increase_or_reduce(node.winline + #node.data, -#node.data)
    return
  end

  local lines = {}
  local text = api.nvim_get_current_line()
  text = text:gsub(config.ui.expand, config.ui.collapse)
  lines[#lines + 1] = text
  for i, v in pairs(node.data) do
    lines[#lines + 1] = v.name
    v.winline = curline + i
  end
  vim.bo[self.bufnr].modifiable = true
  api.nvim_buf_set_lines(self.bufnr, curline - 1, curline, false, lines)
  vim.bo[self.bufnr].modifiable = false
  node.expand = true
  api.nvim_buf_add_highlight(self.bufnr, 0, 'SagaExpand', curline - 1, 0, 5)
  api.nvim_buf_add_highlight(
    self.bufnr,
    0,
    prefix .. kind[node.data[1].kind][1],
    curline - 1,
    5,
    -1
  )
  for _, v in ipairs(node.data) do
    for group, scope in pairs(v.hi_scope) do
      api.nvim_buf_add_highlight(self.bufnr, 0, group, v.winline - 1, scope[1], scope[2])
    end
  end

  increase_or_reduce(node.winline, #node.data)
end

function ot:auto_refresh()
  api.nvim_create_autocmd('BufEnter', {
    group = self.group,
    callback = function(opt)
      local clients = lsp.get_active_clients({ bufnr = opt.buf })
      if next(clients) == nil or opt.buf == self.render_buf then
        return
      end

      vim.bo[self.bufnr].modifiable = true
      api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
      self:outline(opt.buf, true)
    end,
    desc = '[Lspsaga.nvim] outline auto refresh',
  })
end

function ot:auto_preview(symbol_data)
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
    self.preview_winid = nil
    self.preview_bufnr = nil
  end

  local curline = api.nvim_win_get_cursor(0)[1]
  local node
  for _, nodes in pairs(symbol_data) do
    node = find_node(nodes.data, curline)
    if node then
      break
    end
  end
  if not node then
    return
  end

  local range = node.location and node.location.range or node.range
  if not range then
    return
  end

  if range.start.line == range['end'].line then
    range['end'].line = range['end'].line + 1
  end

  local content =
    api.nvim_buf_get_lines(self.render_buf, range.start.line, range['end'].line, false)

  local WIN_WIDTH = vim.o.columns
  local max_width = math.floor(WIN_WIDTH * outline_conf.preview_width)

  local opts = {
    relative = 'editor',
    style = 'minimal',
    height = #content > 0 and #content or 1,
    width = max_width,
    no_size_override = true,
  }

  local winid = fn.bufwinid(self.render_buf)
  local _height = fn.winheight(winid)
  local win_height

  if outline_conf.win_position == 'right' then
    opts.anchor = 'NE'
    opts.col = WIN_WIDTH - outline_conf.win_width - 1
    opts.row = fn.winline() + 2
    win_height = fn.winheight(0)
    if win_height < _height then
      opts.row = (_height - win_height) + fn.winline()
    else
      opts.row = fn.winline()
    end
  else
    opts.anchor = 'NW'
    opts.col = outline_conf.win_width + 1
    win_height = fn.winheight(0)
    if win_height < _height then
      opts.row = (_height - win_height) + vim.fn.winline()
    else
      opts.row = fn.winline()
    end
  end

  local content_opts = {
    contents = content,
    buftype = 'nofile',
    bufhidden = 'wipe',
    highlight = {
      normal = 'ActionPreviewNormal',
      border = 'ActionPreviewBorder',
    },
  }

  self.preview_bufnr, self.preview_winid = window.create_win_with_border(content_opts, opts)

  local lang = vim.treesitter.language.get_lang(vim.bo[self.render_buf].filetype)
  vim.treesitter.start(self.preview_bufnr, lang)

  local events = { 'CursorMoved', 'BufLeave' }
  vim.defer_fn(function()
    util.close_preview_autocmd(self.bufnr, self.preview_winid, events)
  end, 0)
end

function ot:close_when_last()
  api.nvim_create_autocmd('WinEnter', {
    group = self.group,
    callback = function()
      local wins = api.nvim_list_wins()
      if
        (not api.nvim_buf_is_loaded(self.render_buf) or not api.nvim_buf_is_valid(self.render_buf))
        and #wins <= 2
      then
        if #wins == 1 then
          local new = api.nvim_create_buf(false, true)
          api.nvim_win_set_buf(wins[1], new)
        else
          api.nvim_win_close(self.winid, true)
        end
        clean_ctx()
      end
    end,
    desc = 'Outline auto close when last one',
  })
end

function ot:render_outline(buf, symbols)
  if not self.winid and not self.bufnr then
    self.winid, self.bufnr = create_outline_window()
  end

  local res = symbol:category(buf, symbols)

  local lines = {}
  local kind = get_kind() or {}
  local fname = util.get_path_info(buf, 1)
  local data = util.icon_from_devicon(vim.bo[buf].filetype)
  lines[#lines + 1] = ' ' .. data[1] .. fname[1]
  local prefix = get_hi_prefix()
  local hi = {}

  for k, v in pairs(res) do
    local scope = {}
    local indent_with_icon = '  ' .. config.ui.collapse
    lines[#lines + 1] = indent_with_icon .. ' ' .. kind[k][1] .. ':' .. #v.data
    scope['SagaCount'] = { #indent_with_icon + #kind[k][1] + 1, -1 }
    scope['SagaCollapse'] = { 0, #indent_with_icon }
    scope[prefix .. kind[k][1]] = { #indent_with_icon, -1 }
    hi[#hi + 1] = scope
    v.winline = #lines
    for j, node in pairs(v.data) do
      node.hi_scope = {}
      local indent = j == #v.data and '  └' .. '─' or '  ├' .. '─'
      node.name = indent .. kind[node.kind][2] .. node.name
      lines[#lines + 1] = node.name
      node.hi_scope['OutlineIndent'] = { 0, #indent }
      node.hi_scope[prefix .. kind[node.kind][1]] = { #indent, #indent + #kind[node.kind][2] }
      hi[#hi + 1] = node.hi_scope
      node.winline = #lines
    end
    lines[#lines + 1] = ''
    hi[#hi + 1] = {}
  end

  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  vim.bo[self.bufnr].modifiable = false
  api.nvim_buf_add_highlight(self.bufnr, 0, data[2], 0, 0, 4)
  for k, v in pairs(hi) do
    if not vim.tbl_isempty(v) then
      for group, scope in pairs(v) do
        api.nvim_buf_add_highlight(self.bufnr, 0, group, k, scope[1], scope[2])
      end
    end
  end

  self:apply_map(res)
  self:register_events(res)
  self.render_buf = buf

  api.nvim_create_autocmd('WinClosed', {
    callback = function(opt)
      if api.nvim_get_current_win() == self.winid and opt.buf == self.bufnr then
        clean_ctx()
      end
    end,
    desc = '[lspsaga.nvim] clean the outline data after the win closed',
  })
end

function ot:register_events(symbol_data)
  if outline_conf.auto_close then
    self:close_when_last()
  end

  if outline_conf.auto_refresh then
    self:auto_refresh()
  end

  if outline_conf.auto_preview then
    api.nvim_create_autocmd('CursorMoved', {
      group = self.group,
      buffer = self.bufnr,
      callback = function()
        self:auto_preview(symbol_data)
      end,
    })
  end
  self.registerd = true
end

function ot:close_and_clean()
  if self.winid and api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
    clean_ctx()
  end
end

function ot:outline(buf, non_close)
  non_close = non_close or false
  if self.winid and api.nvim_win_is_valid(self.winid) and not non_close then
    self:close_and_clean()
    return
  end

  buf = buf or api.nvim_get_current_buf()

  if self.pending_request then
    vim.notify('[lspsaga.nvim] there is already a request for outline please wait')
    return
  end

  local res = symbol:get_buf_symbols(buf)
  if not res then
    return
  end

  self.group = api.nvim_create_augroup('LspsagaOutline', { clear = false })
  if res.pending_request then
    symbol:push_cb_queue(function(bufnr, symbols)
      self.pending_request = false
      self:render_outline(bufnr, symbols)
    end)
  else
    self:render_outline(buf, res.symbols)
  end
end

return setmetatable(ctx, ot)
