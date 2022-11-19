local ot = {}
local api, lsp, fn, keymap = vim.api, vim.lsp, vim.fn, vim.keymap
local cache = require('lspsaga.symbolwinbar').symbol_cache
local kind = require('lspsaga.lspkind')
local hi_prefix = 'LSOutline'
local space = '  '
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local config = require('lspsaga').config_values
local max_preview_lines = config.max_preview_lines
local outline_conf = config.show_outline
local method = 'textDocument/documentSymbol'

-- alias built in
local insert = table.insert

function ot:init_data(tbl, level)
  local current_buf = api.nvim_get_current_buf()
  local icon, hi, line = '', '', ''

  -- {
  --      table  number  string bool number number
  --    { node, preview_contents, win_line, hi, expand,expand_col,indent }
  -- }
  if self[current_buf].data == nil then
    self[current_buf].data = {}
  end

  for _, node in pairs(tbl) do
    level = level or 1
    icon = kind[node.kind][2]
    hi = hi_prefix .. kind[node.kind][1]
    local indent = string.rep(space, level)
    local indent_with_icon = indent .. icon
    local prev_indent = 2

    local data = self[current_buf].data
    if next(self[current_buf].data) ~= nil then
      _, prev_indent = data[#data].node:find('%s+')
    end

    local tmp_data = {}

    if #indent > prev_indent then
      local text = data[#data].node
      local iwidth = api.nvim_strwidth(outline_conf.icon.expand)
      local tmp = text:sub(0, (prev_indent - iwidth)) .. outline_conf.icon.expand
      data[#data].node = tmp .. text:sub(prev_indent + 1)
      data[#data].expand = true
      data[#data].expand_col = prev_indent + 2
      data[#data].hi_scope = data[#data].hi_scope + 2
    end

    line = indent_with_icon .. node.name

    tmp_data.node = line
    tmp_data.hi = hi
    tmp_data.hi_scope = #indent_with_icon
    tmp_data.win_line = #self[current_buf].data + 1
    tmp_data.indent = #indent
    -- get preview contents
    local range = node.location and node.location.range or node.range
    local _end_line = range['end'].line + 1
    local content = api.nvim_buf_get_lines(current_buf, range.start.line, _end_line, false)
    tmp_data.preview_contents = content
    tmp_data.link = { range.start.line + 1, range.start.character }
    tmp_data.detail = node.detail

    insert(self[current_buf].data, tmp_data)

    if node.children and next(node.children) ~= nil then
      self:init_data(node.children, level + 1)
    end
  end
end

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
end

local function gen_outline_hi()
  for _, v in pairs(kind) do
    api.nvim_set_hl(0, hi_prefix .. v[1], { fg = v[3] })
  end
end

local virt_id = api.nvim_create_namespace('lspsaga_outline')

function ot:detail_virt_text(bufnr, scope)
  scope = scope or { 1, #self[bufnr].data }

  for i = scope[1], scope[2], 1 do
    if self[bufnr].data[i].detail then
      api.nvim_buf_set_extmark(0, virt_id, self[bufnr].data[i].win_line - 1, 0, {
        virt_text = { { self[bufnr].data[i].detail, 'OutlineDetail' } },
        virt_text_pos = 'eol',
      })
    end
  end
end

function ot:get_actual_data_index(bufnr, line)
  if next(self[bufnr].data) == nil then
    return
  end

  for k, v in pairs(self[bufnr].data) do
    if v.win_line == line then
      return k
    end
  end
end

function ot:auto_preview(bufnr)
  if not self[bufnr] or next(self[bufnr].data) == nil then
    return
  end

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end

  local current_line = api.nvim_win_get_cursor(0)[1]
  local actual_index = self:get_actual_data_index(bufnr, current_line)
  local content = self[bufnr].data[actual_index].preview_contents

  local WIN_WIDTH = vim.o.columns
  local max_width = math.floor(WIN_WIDTH * 0.5)
  local max_height = #content

  if max_height > max_preview_lines then
    max_height = max_preview_lines
  end

  local opts = {
    relative = 'editor',
    style = 'minimal',
    height = max_height,
    width = max_width,
  }

  local winid = fn.bufwinid(bufnr)
  if not api.nvim_win_is_valid(winid) then
    return
  end
  local _height = api.nvim_win_get_height(winid)
  local win_height = api.nvim_win_get_height(0)

  if outline_conf.win_position == 'right' then
    opts.anchor = 'NE'
    opts.col = WIN_WIDTH - outline_conf.win_width - 1
  else
    opts.anchor = 'NW'
    opts.col = outline_conf.win_width + 1
  end
  opts.row = win_height < _height and (_height - win_height) + fn.winline() or fn.winline() - 1

  local content_opts = {
    contents = content,
    filetype = self[bufnr].ft,
    highlight = 'LSOutlinePreviewBorder',
  }

  opts.noautocmd = true

  self.preview_bufnr, self.preview_winid = window.create_win_with_border(content_opts, opts)

  local events = { 'CursorMoved', 'BufLeave' }
  vim.defer_fn(function()
    libs.close_preview_autocmd(self.winbuf, self.preview_winid, events)
  end, 100)
end

function ot:expand_collaspe(bufnr)
  local current_line = api.nvim_win_get_cursor(self.winid)[1]

  local current_text = api.nvim_get_current_line()

  local data = self[bufnr].data
  local actual_indent, actual_index, _end_index
  for k, v in pairs(data) do
    if v.win_line == current_line and not actual_indent then
      actual_indent = v.indent
      actual_index = k
    end
    if
      actual_indent
      and (v.indent == actual_indent or v.indent < actual_indent)
      and v.win_line > current_line
    then
      _end_index = k
      break
    end
    if k == #data and not _end_index then
      _end_index = k
    end
  end

  api.nvim_buf_set_option(self.winbuf, 'modifiable', true)

  if data[actual_index].expand then
    local _end_pos = _end_index ~= #data and data[_end_index].win_line
      or data[_end_index].win_line + 1
    current_text = current_text:gsub(outline_conf.icon.expand, outline_conf.icon.collaspe)
    local _, pos = current_text:find(outline_conf.icon.collaspe)
    api.nvim_buf_set_lines(self.winbuf, current_line - 1, _end_pos - 1, false, { current_text })
    api.nvim_buf_set_option(self.winbuf, 'modifiable', false)
    data[actual_index].expand = false
    api.nvim_buf_add_highlight(self.winbuf, 0, 'OutlineCollaspe', current_line - 1, 0, pos)
    api.nvim_buf_add_highlight(
      self.winbuf,
      0,
      data[actual_index].hi,
      current_line - 1,
      pos + 1,
      data[actual_index].hi_scope
    )
    for _, v in pairs(data) do
      if v.win_line > current_line then
        v.win_line = v.win_line - (_end_pos - current_line - 1)
      end
    end
    self:detail_virt_text(bufnr, { actual_index, actual_index })
    return
  end

  local lines = {}
  _end_index = _end_index == #data and _end_index + 1 or _end_index
  for i = actual_index, _end_index - 1 do
    insert(lines, data[i].node)
  end
  lines[1] = api.nvim_get_current_line()
  lines[1] = lines[1]:gsub(outline_conf.icon.collaspe, outline_conf.icon.expand)
  api.nvim_buf_set_lines(self.winbuf, current_line - 1, current_line, false, lines)
  api.nvim_buf_set_option(self.winbuf, 'modifiable', false)
  data[actual_index].expand = true
  --update data
  for i = actual_index + 1, #data do
    data[i].win_line = data[i].win_line + (_end_index - actual_index - 1)
  end
  for i = actual_index, _end_index - 1 do
    api.nvim_buf_add_highlight(
      self.winbuf,
      0,
      data[i].hi,
      data[i].win_line - 1,
      0,
      data[i].hi_scope
    )
    if data[i].expand_col then
      api.nvim_buf_add_highlight(
        self.winbuf,
        0,
        'OutlineExpand',
        data[i].win_line - 1,
        0,
        data[i].expand_col
      )
    end
  end
  _end_index = _end_index == #data + 1 and _end_index - 1 or _end_index
  self:detail_virt_text(bufnr, { actual_index, _end_index })
end

function ot:jump_to_line(bufnr)
  local current_line = api.nvim_win_get_cursor(0)[1]
  local actual_index = self:get_actual_data_index(bufnr, current_line)
  local pos = self[bufnr].data[actual_index].link
  local win = fn.win_findbuf(bufnr)[1]
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, pos)
end

local create_outline_window = function()
  if #outline_conf.win_with > 0 then
    local ok, sp_buf = libs.find_buffer_by_filetype(outline_conf.win_with)

    if ok then
      local winid = fn.win_findbuf(sp_buf)[1]
      api.nvim_set_current_win(winid)
      vim.cmd('noautocmd sp vnew')
      return
    end
  end

  local pos = outline_conf.win_position == 'right' and 'botright' or 'topleft'
  vim.cmd('noautocmd ' .. pos .. ' vsplit')
  vim.cmd('vertical resize ' .. config.show_outline.win_width)
end

---@private
local request_and_render = function()
  local bufnr = api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params(bufnr) }
  local client = libs.get_client_by_cap('documentSymbolProvider')

  if not client then
    return
  end

  client.request(method, params, function(_, result)
    if not result or next(result) == nil then
      return
    end

    local symbols = result
    ot:update_outline(symbols)
  end, bufnr)
end

function ot:set_buf_contents(bufnr)
  local nodes = {}
  for _, v in pairs(self[bufnr].data) do
    insert(nodes, v.node)
  end
  api.nvim_buf_set_lines(self.winbuf, 0, -1, false, nodes)
end

function ot:set_keymap(bufnr)
  keymap.set('n', outline_conf.keys.jump, function()
    self:jump_to_line(bufnr)
  end, {
    buffer = self.winbuf,
  })

  keymap.set('n', outline_conf.keys.expand_collaspe, function()
    self:expand_collaspe(bufnr)
  end, {
    buffer = self.winbuf,
  })

  keymap.set('n', outline_conf.keys.quit, function()
    window.nvim_close_valid_window(self.winid)
  end)
end

function ot:update_outline(symbols, in_refresh)
  in_refresh = in_refresh or nil
  local current_buf = api.nvim_get_current_buf()
  self[current_buf] = { ft = vim.bo.filetype }

  self:init_data(symbols)

  gen_outline_hi()

  if not self.winid then
    create_outline_window()
    self.winid = api.nvim_get_current_win()
    self.winbuf = api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(self.winid, self.winbuf)
    set_local()
  else
    if not api.nvim_buf_get_option(self.winbuf, 'modifiable') then
      api.nvim_buf_set_option(self.winbuf, 'modifiable', true)
    end
  end

  self:set_buf_contents(current_buf)

  for k, v in pairs(self) do
    if type(v) == 'table' and self[k].in_render then
      self[k].in_render = false
    end
  end

  self[current_buf].in_render = true

  if config.show_outline.show_detail then
    self:detail_virt_text(current_buf)
  end

  api.nvim_buf_set_option(self.winbuf, 'modifiable', false)

  for i, data in pairs(self[current_buf].data) do
    api.nvim_buf_add_highlight(self.winbuf, 0, data.hi, i - 1, 0, data.hi_scope)
    if data.expand_col then
      api.nvim_buf_add_highlight(self.winbuf, 0, 'OutlineExpand', i - 1, 0, data.expand_col)
    end
  end

  self:set_keymap(current_buf)
  if not in_refresh then
    self:preview_event(current_buf)
  end
  self:refresh_event()
  self.render_status = true

  api.nvim_buf_attach(self.winbuf, false, {
    on_detach = function()
      self:remove_events()
    end,
  })
end

function ot:find_in_render_buf()
  for buf, v in pairs(self) do
    if type(v) == 'table' and self[buf].in_render then
      return buf
    end
  end
end

function ot:refresh_event()
  if not outline_conf.auto_refresh then
    return
  end

  self.refresh_au = api.nvim_create_autocmd('BufEnter', {
    callback = function()
      if vim.bo.filetype == 'lspsagaoutline' then
        return
      end

      if vim.bo.buftype == 'nofile' or vim.bo.buftype == 'prompt' then
        return
      end

      local buf = api.nvim_get_current_buf()
      local in_render_buf = self:find_in_render_buf()
      if buf == in_render_buf then
        return
      end

      -- don't render when the buffer is unnamed buffer
      if #api.nvim_buf_get_name(buf) == 0 then
        return
      end

      -- when the buffer not have lsp client
      local clients = lsp.get_active_clients({ buffer = buf })
      if next(clients) == nil then
        return
      end

      if not cache[buf] or next(cache[buf]) == nil then
        request_and_render()
        return
      end
      self:update_outline(cache[buf], true)
    end,
  })
end

function ot:preview_event(bufnr)
  if not outline_conf.auto_preview then
    return
  end
  self:auto_preview(bufnr)
  self.preview_au = api.nvim_create_autocmd('CursorMoved', {
    buffer = self.winbuf,
    callback = function()
      local buf
      for k, v in pairs(self) do
        if type(v) == 'table' and v.in_render then
          buf = k
          break
        end
      end

      self:auto_preview(buf)
    end,
    desc = 'Lspsaga Outline Preview',
  })
end

function ot:remove_events()
  pcall(api.nvim_del_augroup_by_id, self.refresh_au)
  pcall(api.nvim_del_augroup_by_id, self.preview_au)
end

function ot:clear_data()
  for i, v in pairs(self) do
    if type(v) ~= 'function' then
      self[i] = nil
    end
  end
end

function ot:render_outline()
  if self.render_status then
    window.nvim_close_valid_window(self.winid)
    self:clear_data()
    return
  end
  local current_buf = api.nvim_get_current_buf()

  -- if buffer not lsp client
  local clients = lsp.get_active_clients({ buffer = current_buf })
  if next(clients) == nil then
    return
  end

  if cache[current_buf] and next(cache[current_buf]) ~= nil then
    self:update_outline(cache[current_buf])
    return
  end

  request_and_render()
end

return ot
