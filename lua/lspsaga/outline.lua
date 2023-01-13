local ot = {}
local api, lsp, fn, keymap = vim.api, vim.lsp, vim.fn, vim.keymap
local config = require('lspsaga').config
local libs = require('lspsaga.libs')
local symbar = require('lspsaga.symbolwinbar')
local outline_conf = config.outline
local insert = table.insert
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

local function get_cache_symbols(buf)
  if not symbar[buf] then
    return
  end
  local data = symbar[buf]
  if not data or data.pending_request then
    return
  end
  if not data.pending_request and data.symbols then
    return data.symbols
  end
  return nil
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
  }
  for opt, val in pairs(local_options) do
    vim.opt_local[opt] = val
  end
  ---@diagnostic disable-next-line: undefined-field
  if fn.has('nvim-0.9') == 1 and #vim.opt_local.stc:get() > 0 then
    vim.opt_local.stc = ''
  end
end

local function get_hi_prefix()
  return 'LSOutline'
end

local function get_kind()
  return require('lspsaga.highlight').get_kind()
end

local function find_node(data, line)
  for idx, node in pairs(data or {}) do
    if node.winline == line then
      return idx, node
    end
  end
end

local function parse_symbols(buf, symbols)
  local res = {}

  local tmp_node = function(node)
    local tmp = {}
    tmp.winline = -1
    for k, v in pairs(node) do
      if k ~= 'children' then
        tmp[k] = v
      end
    end
    return tmp
  end

  local function recursive_parse(tbl)
    for _, v in pairs(tbl) do
      if not res[v.kind] then
        res[v.kind] = {
          expand = true,
          data = {},
        }
      end
      if not symbar.node_is_keyword(buf, v) then
        local tmp = tmp_node(v)
        insert(res[v.kind].data, tmp)
      end
      if v.children then
        recursive_parse(v.children)
      end
    end
  end
  recursive_parse(symbols)
  local keys = vim.tbl_keys(res)
  table.sort(keys, outline_conf.custom_sort)
  local new = {}
  for _, v in pairs(keys) do
    new[v] = res[v]
  end

  -- remove unnecessary data reduce memory usage
  for k, v in pairs(new) do
    if #v.data == 0 then
      new[k] = nil
    else
      for _, item in pairs(v.data) do
        if item.selectionRange then
          item.pos = { item.selectionRange.start.line, item.selectionRange.start.character }
          item.selectionRange = nil
        end
      end
    end
  end

  return new
end

---@private
local function create_outline_window()
  if #outline_conf.win_with > 0 then
    local ok, sp_buf = libs.find_buffer_by_filetype(outline_conf.win_with)

    if ok then
      local winid = fn.win_findbuf(sp_buf)[1]
      api.nvim_set_current_win(winid)
      vim.cmd('sp vnew')
      return
    end
  end

  local pos = outline_conf.win_position == 'right' and 'botright' or 'topleft'
  vim.cmd(pos .. ' vnew')
  vim.cmd('vertical resize ' .. outline_conf.win_width)
  set_local()
  return api.nvim_get_current_win(), api.nvim_get_current_buf()
end

function ot:apply_map()
  local maps = outline_conf.keys
  local opt = { buffer = true, nowait = true }
  keymap.set('n', maps.quit, function()
    if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) then
      api.nvim_buf_delete(self.bufnr, { force = true })
    end
    if self.winid and api.nvim_win_is_valid(self.winid) then
      api.nvim_win_close(self.winid, true)
    end
    clean_ctx()
  end, opt)

  keymap.set('n', maps.expand_collaspe, function()
    self:expand_collaspe()
  end, opt)

  keymap.set('n', maps.jump, function()
    local curline = api.nvim_win_get_cursor(0)[1]
    local node
    for _, nodes in pairs(self.data) do
      _, node = find_node(nodes.data, curline)
      if node then
        break
      end
    end

    if not node or not node.range then
      return
    end

    local winid = fn.bufwinid(self.render_buf)
    api.nvim_set_current_win(winid)
    api.nvim_win_set_cursor(winid, { node.pos[1] + 1, node.pos[2] })
    local width = #api.nvim_get_current_line()
    libs.jump_beacon({ node.range.start.line, node.range.start.character }, width)
  end, opt)
end

function ot:request_and_render(buf)
  local params = { textDocument = lsp.util.make_text_document_params(buf) }
  local client = libs.get_client_by_cap('documentSymbolProvider')
  if not client then
    return
  end

  client.request('textDocument/documentSymbol', params, function(_, result)
    self.pending_request = false
    if not result or next(result) == nil then
      return
    end
    self:render_outline(buf, result)
    if not self.registerd then
      self:register_events()
    end
  end, buf)
end

function ot:expand_collaspe()
  local curline = api.nvim_win_get_cursor(0)[1]
  local idx, node = find_node(self.data, curline)
  if not node then
    return
  end
  local prefix = get_hi_prefix()
  local kind = get_kind()

  local function increase_or_reduce(pos, num)
    for k, v in pairs(self.data) do
      if pos > k then
        for _, item in pairs(v.data) do
          item.winline = item.winline + num
        end
      end
    end
  end

  if node.expand then
    local text = api.nvim_get_current_line()
    text = text:gsub(config.ui.collaspe, config.ui.expand)
    for _, v in pairs(node.data) do
      v.winline = -1
    end
    api.nvim_buf_set_lines(self.bufnr, curline - 1, curline + #node.data, false, { text })
    node.expand = false
    api.nvim_buf_add_highlight(self.bufnr, 0, 'SagaCollaspe', curline - 1, 0, 5)
    api.nvim_buf_add_highlight(
      self.bufnr,
      0,
      prefix .. kind[node.data[1].kind][1],
      curline - 1,
      5,
      -1
    )
    increase_or_reduce(idx, -#node.data)
    return
  end

  local lines = {}
  local text = api.nvim_get_current_line()
  text = text:gsub(config.ui.expand, config.ui.collaspe)
  insert(lines, text)
  for i, v in pairs(node.data) do
    insert(lines, v.name)
    v.winline = curline + i
  end
  api.nvim_buf_set_lines(self.bufnr, curline - 1, curline, false, lines)
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
  for _, v in pairs(node.data) do
    for group, scope in pairs(v.hi_scope) do
      api.nvim_buf_add_highlight(self.bufnr, 0, group, v.winline - 1, scope[1], scope[2])
    end
  end

  increase_or_reduce(idx, #node.data)
end

function ot:auto_refresh()
  api.nvim_create_autocmd('BufEnter', {
    group = self.group,
    callback = function(opt)
      local ignore = { 'lspsagaoutline', 'terminal', 'help' }
      if vim.tbl_contains(ignore, vim.bo[opt.buf].filetype) or opt.buf == self.render_buf then
        return
      end

      if vim.bo[opt.buf].buftype == 'prompt' then
        return
      end

      if #api.nvim_buf_get_name(opt.buf) == 0 then
        return
      end

      --set a delay in there if change buffer quickly only render last one
      vim.defer_fn(function()
        if api.nvim_get_current_buf() ~= opt.buf or not self.bufnr then
          return
        end
        api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
        self:outline(true)
      end, 10)
    end,
    desc = '[Lspsaga.nvim] outline auto refresh',
  })
end

function ot:auto_preview()
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end

  local curline = api.nvim_win_get_cursor(0)[1]
  local node
  for _, nodes in pairs(self.data) do
    _, node = find_node(nodes.data, curline)
    if node then
      break
    end
  end

  if not node or not node.range then
    return
  end

  local content = api.nvim_buf_get_lines(
    self.render_buf,
    node.range.start.line,
    node.range['end'].line + config.preview.lines_below,
    false
  )

  local WIN_WIDTH = vim.o.columns
  local max_width = math.floor(WIN_WIDTH * 0.5)

  local opts = {
    relative = 'editor',
    style = 'minimal',
    height = #content,
    width = max_width,
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
  opts.noautocmd = true

  local content_opts = {
    contents = content,
    buftype = 'nofile',
    filetype = vim.bo[self.render_buf].filetype,
    highlight = {
      normal = 'ActionPreviewNormal',
      border = 'ActionPreviewBorder',
    },
  }

  local window = require('lspsaga.window')
  self.preview_bufnr, self.preview_winid = window.create_win_with_border(content_opts, opts)

  local events = { 'CursorMoved', 'BufLeave' }
  vim.defer_fn(function()
    libs.close_preview_autocmd(self.bufnr, self.preview_winid, events)
  end, 0)
end

function ot:close_when_last()
  api.nvim_create_autocmd('BufEnter', {
    group = self.group,
    callback = function(opt)
      local wins = api.nvim_list_wins()
      if #wins == 1 and vim.bo[opt.buf].filetype == 'lspsagaoutline' then
        api.nvim_buf_delete(self.bufnr, { force = true })
        local bufnr = api.nvim_create_buf(true, true)
        api.nvim_win_set_buf(0, bufnr)
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

  local res = parse_symbols(buf, symbols)
  self.data = res
  local lines = {}
  local kind = get_kind()
  local fname = libs.get_path_info(buf, 1)
  local data = libs.icon_from_devicon(vim.bo[buf].filetype)
  ---@diagnostic disable-next-line: need-check-nil
  insert(lines, ' ' .. data[1] .. ' ' .. fname[1])
  local prefix = get_hi_prefix()
  local hi = {}

  for k, v in pairs(res) do
    local scope = {}
    local indent_with_icon = '  ' .. config.ui.collaspe
    insert(lines, indent_with_icon .. ' ' .. kind[k][1])
    scope['SagaCollaspe'] = { 0, #indent_with_icon }
    scope[prefix .. kind[k][1]] = { #indent_with_icon, -1 }
    insert(hi, scope)
    v.winline = #lines
    for j, node in pairs(v.data) do
      node.hi_scope = {}
      local indent = j == #v.data and '  └' .. '─' or '  ├' .. '─'
      node.name = indent .. kind[node.kind][2] .. node.name
      insert(lines, node.name)
      node.hi_scope['OutlineIndent'] = { 0, #indent }
      node.hi_scope[prefix .. kind[node.kind][1]] = { #indent, #indent + #kind[node.kind][2] }
      insert(hi, node.hi_scope)
      node.winline = #lines
    end
    table.insert(lines, '')
    table.insert(hi, {})
  end

  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  api.nvim_buf_add_highlight(self.bufnr, 0, data[2], 0, 0, 4)
  for k, v in pairs(hi) do
    if not vim.tbl_isempty(v) then
      for group, scope in pairs(v) do
        api.nvim_buf_add_highlight(self.bufnr, 0, group, k, scope[1], scope[2])
      end
    end
  end
  self:apply_map()
end

function ot:register_events()
  api.nvim_create_autocmd('BufDelete', {
    group = self.group,
    buffer = self.bufnr,
    callback = function()
      clean_ctx()
    end,
  })

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
        self:auto_preview()
      end,
    })
  end
  self.registerd = true
end

function ot:outline(quiet)
  quiet = quiet or false
  if self.pending_request and not quiet then
    vim.notify('[lspsaga.nvim] there already have a request for outline please wait')
    return
  end
  local current_buf = api.nvim_get_current_buf()
  local symbols = get_cache_symbols(current_buf)
  self.group = api.nvim_create_augroup('LspsagaOutline', { clear = true })
  self.render_buf = current_buf
  if not symbols then
    self.pending_request = true
    self:request_and_render(current_buf)
  else
    self:render_outline(current_buf, symbols)
    if not self.registerd then
      self:register_events()
    end
  end
end

return setmetatable(ctx, ot)
