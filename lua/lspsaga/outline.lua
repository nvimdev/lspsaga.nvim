local ot = {}
local api, lsp = vim.api, vim.lsp
local symbar = require('lspsaga.symbolwinbar')
local cache = symbar.symbol_cache
local kind = require('lspsaga.lspkind')
local hi_prefix = 'LSOutline'
local space = '  '
local saga_group = require('lspsaga').saga_group
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local config = require('lspsaga').config_values
local max_preview_lines = config.max_preview_lines
local outline_conf = config.show_outline
local method = 'textDocument/documentSymbol'

local function nodes_with_icon(tbl, nodes, hi_tbl, level)
  local current_buf = api.nvim_get_current_buf()
  local icon, hi, line = '', '', ''

  for _, node in pairs(tbl) do
    level = level or 1
    icon = kind[node.kind][2]
    hi = hi_prefix .. kind[node.kind][1]
    local indent = string.rep(space, level)

    line = indent .. icon .. node.name
    table.insert(nodes, line)
    table.insert(hi_tbl, hi)
    if ot[current_buf].preview_contents == nil then
      ot[current_buf].preview_contents = {}
      ot[current_buf].link = {}
      ot[current_buf].details = {}
    end
    local range = node.location ~= nil and node.location.range or node.range
    local _end_line = range['end'].line + 1
    local content = api.nvim_buf_get_lines(current_buf, range.start.line, _end_line, false)
    table.insert(ot[current_buf].preview_contents, content)
    table.insert(ot[current_buf].link, { range.start.line + 1, range.start.character })
    table.insert(ot[current_buf].details, node.detail)

    if node.children ~= nil and next(node.children) ~= nil then
      nodes_with_icon(node.children, nodes, hi_tbl, level + 1)
    end
  end
end

local function get_all_nodes(symbols)
  local nodes, hi_tbl = {}, {}
  local current_buf = api.nvim_get_current_buf()
  symbols = symbols or cache[current_buf]

  nodes_with_icon(symbols, nodes, hi_tbl)

  return nodes, hi_tbl
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
    foldmethod = 'expr',
    foldexpr = "v:lua.require'lspsaga.outline'.set_fold()",
    foldtext = "v:lua.require'lspsaga.outline'.set_foldtext()",
    fillchars = { eob = '-', fold = ' ' },
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

function ot.set_foldtext()
  local line = vim.fn.getline(vim.v.foldstart)
  return outline_conf.fold_prefix .. line
end

function ot.set_fold()
  local cur_indent = vim.fn.indent(vim.v.lnum)
  local next_indent = vim.fn.indent(vim.v.lnum + 1)

  if cur_indent == next_indent then
    return (cur_indent / vim.bo.shiftwidth) - 1
  elseif next_indent < cur_indent then
    return (cur_indent / vim.bo.shiftwidth) - 1
  elseif next_indent > cur_indent then
    return '>' .. (next_indent / vim.bo.shiftwidth) - 1
  end
end

local virt_id = api.nvim_create_namespace('lspsaga_outline')
local virt_hi = { 'OutlineIndentOdd', 'OutlineIndentEvn' }

function ot:fold_indent_virt(tbl)
  local level, col = 0, 0
  local virt_with_hi = {}
  for index, _ in pairs(tbl) do
    level = vim.fn.foldlevel(index)
    if level > 0 then
      for i = 1, level do
        if bit.band(i, 1) == 1 then
          col = i == 1 and i - 1 or col + 2
          virt_with_hi = { { outline_conf.virt_text, virt_hi[1] } }
        else
          col = col + 2
          virt_with_hi = { { outline_conf.virt_text, virt_hi[2] } }
        end

        api.nvim_buf_set_extmark(0, virt_id, index - 1, col, {
          virt_text = virt_with_hi,
          virt_text_pos = 'overlay',
        })
      end
    end
  end
end

function ot:detail_virt_text(bufnr)
  if not self[bufnr].details then
    return
  end

  for i, detail in pairs(self[bufnr].details) do
    api.nvim_buf_set_extmark(0, virt_id, i - 1, 0, {
      virt_text = { { detail, 'OutlineDetail' } },
      virt_text_pos = 'eol',
    })
  end
end

function ot:auto_preview(bufnr)
  if self[bufnr] == nil and next(self[bufnr]) == nil then
    return
  end

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end

  local current_line = api.nvim_win_get_cursor(0)[1]
  local content = self[bufnr].preview_contents[current_line]

  local WIN_WIDTH = api.nvim_get_option('columns')
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

  local winid = vim.fn.bufwinid(bufnr)
  local _height = vim.fn.winheight(winid)
  local win_height

  if outline_conf.win_position == 'right' then
    opts.anchor = 'NE'
    opts.col = WIN_WIDTH - outline_conf.win_width - 1
    opts.row = vim.fn.winline()
    win_height = vim.fn.winheight(0)
    if win_height < _height then
      opts.row = (_height - win_height) + vim.fn.winline()
    else
      opts.row = vim.fn.winline()
    end
  else
    opts.anchor = 'NW'
    opts.col = outline_conf.win_width + 1
    win_height = vim.fn.winheight(0)
    if win_height < _height then
      opts.row = (_height - win_height) + vim.fn.winline()
    else
      opts.row = vim.fn.winline()
    end
  end

  local content_opts = {
    contents = content,
    filetype = self[bufnr].ft,
    highlight = 'LSOutlinePreviewBorder',
  }

  opts.noautocmd = true

  self.preview_bufnr, self.preview_winid = window.create_win_with_border(content_opts, opts)
  api.nvim_win_set_var(0, 'outline_preview_win', { self.preview_bufnr, self.preview_winid })

  local events = { 'CursorMoved', 'BufLeave' }
  local outline_bufnr = api.nvim_get_current_buf()
  vim.defer_fn(function()
    libs.close_preview_autocmd(outline_bufnr, self.preview_winid, events)
  end, 0)
end

function ot:jump_to_line(bufnr)
  local current_line = api.nvim_win_get_cursor(0)[1]
  local pos = self[bufnr].link[current_line]
  local win = vim.fn.win_findbuf(bufnr)[1]
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, pos)
end

function ot:render_status()
  self.winid = api.nvim_get_current_win()
  self.winbuf = api.nvim_get_current_buf()
  self.status = true
end

local create_outline_window = function()
  if string.len(outline_conf.win_with) > 0 then
    local ok, sp_buf = libs.find_buffer_by_filetype(outline_conf.win_with)

    if ok then
      local winid = vim.fn.win_findbuf(sp_buf)[1]
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
local do_symbol_request = function()
  local bufnr = api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params(bufnr) }
  local client = libs.get_client_by_cap('documentSymbolProvider')

  if not client then
    vim.notify('[Lspsaga] Server of this buffer not support ' .. method)
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

function ot:update_outline(symbols, refresh)
  local current_buf = api.nvim_get_current_buf()
  local current_win = api.nvim_get_current_win()
  self[current_buf] = { ft = vim.bo.filetype }

  local nodes, hi_tbl = get_all_nodes(symbols)

  gen_outline_hi()

  if self.winid == nil then
    create_outline_window()
    self.winid = vim.api.nvim_get_current_win()
    self.winbuf = vim.api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(self.winid, self.winbuf)
    set_local()
  else
    if not api.nvim_buf_get_option(self.winbuf, 'modifiable') then
      api.nvim_buf_set_option(self.winbuf, 'modifiable', true)
    end
    current_win = api.nvim_get_current_win()
    api.nvim_set_current_win(self.winid)
  end

  self:render_status()

  api.nvim_buf_set_lines(self.winbuf, 0, -1, false, nodes)

  self:fold_indent_virt(nodes)

  self:detail_virt_text(current_buf)

  api.nvim_buf_set_option(self.winbuf, 'modifiable', false)

  for i, hi in pairs(hi_tbl) do
    api.nvim_buf_add_highlight(self.winbuf, 0, hi, i - 1, 0, -1)
  end

  if not outline_conf.auto_enter or refresh then
    api.nvim_set_current_win(current_win)
    self.bufenter_id = api.nvim_create_autocmd('BufEnter', {
      group = saga_group,
      callback = function()
        if vim.bo.filetype == 'lspsagaoutline' then
          self:preview_events()
        end
      end,
      desc = 'Lspsaga Outline jump to outline show preview',
    })
  else
    self:preview_events()
  end

  self[current_buf].in_render = true

  vim.keymap.set('n', outline_conf.jump_key, function()
    self:jump_to_line(current_buf)
  end, {
    buffer = self.winbuf,
  })

  api.nvim_buf_attach(self.winbuf, false, {
    on_detach = function()
      self:remove_events()
      if self.bufenter_id then
        pcall(api.nvim_del_autocmd, self.bufenter_id)
        self.bufenter_id = nil
      end
    end,
  })
end

function ot:preview_events()
  if outline_conf.auto_preview then
    self.preview_au = api.nvim_create_autocmd('CursorMoved', {
      group = saga_group,
      buffer = self.winbuf,
      callback = function()
        local buf
        for k, v in pairs(self) do
          if type(v) == 'table' and v.in_render then
            buf = k
          end
        end

        vim.defer_fn(function()
          local cwin = api.nvim_get_current_win()
          if cwin ~= self.winid then
            return
          end
          ot:auto_preview(buf)
        end, 0.5)
      end,
      desc = 'Lspsaga Outline Preview',
    })
  end
end

local outline_exclude = {
  ['lspsagaoutline'] = true,
  ['lspsagafinder'] = true,
  ['lspsagahover'] = true,
  ['sagasignature'] = true,
  ['sagacodeaction'] = true,
  ['sagarename'] = true,
  ['NvimTree'] = true,
  ['NeoTree'] = true,
  ['TelescopePrompt'] = true,
}

function ot:refresh_events()
  if outline_conf.auto_refresh then
    self.refresh_au = api.nvim_create_autocmd('BufEnter', {
      group = saga_group,
      callback = function()
        local current_buf = api.nvim_get_current_buf()
        local in_render = function()
          if self[current_buf] == nil then
            return false
          end

          if self[current_buf].in_render == nil then
            return false
          end

          return self[current_buf].in_render == true
        end

        if not outline_exclude[vim.bo.filetype] and not in_render() then
          self:render_outline(true)
        end
      end,
      desc = 'Outline refresh',
    })
  end
end

function ot:remove_events()
  if self.refresh_au and self.refresh_au > 0 then
    pcall(api.nvim_del_autocmd, self.refresh_au)
    self.refresh_au = nil
  end

  if self.preview_au and self.preview_au > 0 then
    pcall(api.nvim_del_autocmd, self.preview_au)
    self.preview_au = nil
  end
end

function ot:render_outline(refresh)
  refresh = refresh or false

  if self.status and not refresh then
    if api.nvim_buf_is_loaded(self.winbuf) then
      api.nvim_buf_delete(self.winbuf, { force = true })
    end

    window.nvim_close_valid_window(self.winid)
    self.winid = nil
    self.winbuf = nil
    self.status = false
    return
  end

  if not config.symbol_in_winbar.enable and not config.symbol_in_winbar.in_custom then
    do_symbol_request()
    return
  end

  local current_buf = api.nvim_get_current_buf()
  --if cache does not have value also do request
  if cache[current_buf] == nil or next(cache[current_buf][2]) == nil then
    do_symbol_request()
    return
  end

  self:update_outline(nil, refresh)

  if refresh then
    for k, v in pairs(self) do
      if type(v) == 'table' and v.in_render then
        if k ~= current_buf then
          v.in_render = false
        end
      end
    end
  end

  self:refresh_events()
end

function ot:auto_refresh()
  self:update_outline()
end

return ot
