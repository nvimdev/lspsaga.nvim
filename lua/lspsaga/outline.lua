local ot = {}
local api, lsp = vim.api, vim.lsp
local symbar = require('lspsaga.symbolwinbar')
local cache = symbar.symbol_cache
local kind = require('lspsaga.lspkind')
local hi_prefix = 'LSOutline'
local space = '  '
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local group = require('lspsaga').saga_group
local config = require('lspsaga').config_values
local max_preview_lines = config.max_preview_lines
local outline_conf = config.show_outline
local method = 'textDocument/documentSymbol'

---TODO: better ui of outline
local function nodes_with_icon(tbl, nodes, hi_tbl, level)
  local current_buf = api.nvim_get_current_buf()
  local icon, hi = '', ''

  for _, node in pairs(tbl) do
    level = level or 1
    icon = kind[node.kind][2]
    hi = hi_prefix .. kind[node.kind][1]
    local indent = string.rep(space, level)

    -- I think no need to show function param
    if node.kind ~= 14 then
      table.insert(nodes, indent .. icon .. node.name)
      table.insert(hi_tbl, hi)
      if ot[current_buf].preview_contents == nil then
        ot[current_buf].preview_contents = {}
        ot[current_buf].link = {}
      end
      local range = node.location ~= nil and node.location.range or node.range
      local _end_line = range['end'].line + 1
      local content = api.nvim_buf_get_lines(current_buf, range.start.line, _end_line, false)
      table.insert(ot[current_buf].preview_contents, content)
      table.insert(ot[current_buf].link, { range.start.line + 1, range.start.character })
    end

    if node.children ~= nil and next(node.children) ~= nil then
      nodes_with_icon(node.children, nodes, hi_tbl, level + 1)
    end
  end
end

local function get_all_nodes(symbols)
  symbols = symbols or nil
  local nodes, hi_tbl = {}, {}
  local current_buf = api.nvim_get_current_buf()
  if cache[current_buf] ~= nil and next(cache[current_buf][2]) ~= nil and symbols == nil then
    symbols = cache[current_buf][2]
  end

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

function ot:auto_preview(bufnr)
  if self[bufnr] == nil and next(self[bufnr]) == nil then
    return
  end

  local ok, preview_data = pcall(api.nvim_win_get_var, 0, 'outline_preview_win')
  if ok then
    window.nvim_close_valid_window(preview_data[2])
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

  if outline_conf.win_position == 'right' then
    opts.anchor = 'NE'
    opts.col = WIN_WIDTH - outline_conf.win_width - 1
    local folded = vim.fn.foldclosed(current_line)

    ---TODO: smart previe row with fold
    if folded < 0 and vim.v.foldstart == 0 then
      opts.row = current_line - 1
    elseif folded > 0 then
      if current_line == vim.v.foldstart then
        opts.row = current_line - 1
      end
    elseif folded < 0 and vim.v.foldstart > 0 then
      opts.row = current_line - vim.v.foldend + vim.v.foldstart
    end

  else
    opts.anchor = 'NW'
    opts.col = outline_conf.win_width + 1
  end

  local content_opts = {
    contents = content,
    filetype = self[bufnr].ft,
    highlight = 'LSOutlinePreviewBorder',
  }

  local preview_bufnr, preview_winid = window.create_win_with_border(content_opts, opts)
  api.nvim_win_set_var(0, 'outline_preview_win', { preview_bufnr, preview_winid })

  local events = { 'CursorMoved', 'BufLeave' }
  local outline_bufnr = api.nvim_get_current_buf()
  vim.defer_fn(function()
    libs.close_preview_autocmd(outline_bufnr, preview_winid, events)
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
  self.status = true
end

local create_outline_window = function()
  if outline_conf.win_position == 'right' then
    vim.cmd('noautocmd vsplit')
    vim.cmd('vertical resize ' .. config.show_outline.win_width)
    ot:render_status()
    return
  end

  local user_option = vim.opt.splitright:get()

  if user_option then
    vim.opt.splitright = false
  end

  if string.len(outline_conf.left_with) > 0 then
    local ok, sp_buf = libs.find_buffer_by_filetype(outline_conf.left_with)

    if ok then
      local winid = vim.fn.win_findbuf(sp_buf)[1]
      api.nvim_set_current_win(winid)
      vim.cmd('noautocmd sp vnew')
      ot:render_status()
      return
    end
  end

  vim.cmd('noautocmd vnew')
  vim.cmd('vertical resize ' .. config.show_outline.win_width)
  vim.opt.splitright = user_option
  ot:render_status()
end

---@private
local do_symbol_request = function()
  local params = { textDocument = lsp.util.make_text_document_params() }
  lsp.buf_request_all(0, method, params, function(result)
    if libs.result_isempty(result) then
      return
    end

    local client_id = symbar.get_clientid()

    local symbols = result[client_id].result
    ot:update_outline(symbols)
  end)
end

function ot:update_outline(symbols)
  local current_buf = api.nvim_get_current_buf()
  self[current_buf] = { ft = vim.bo.filetype }
  local nodes, hi_tbl = get_all_nodes(symbols)

  gen_outline_hi()

  create_outline_window()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, true)
  api.nvim_win_set_buf(win, buf)

  set_local()

  api.nvim_buf_set_lines(buf, 0, -1, false, nodes)

  api.nvim_buf_set_option(buf, 'modifiable', false)

  for i, hi in pairs(hi_tbl) do
    api.nvim_buf_add_highlight(buf, 0, hi, i - 1, 0, -1)
  end

  if outline_conf.auto_preview then
    api.nvim_create_autocmd('CursorMoved', {
      group = group,
      buffer = buf,
      callback = function()
        ot:auto_preview(current_buf)
      end,
    })
  end

  vim.keymap.set('n', outline_conf.jump_key, function()
    ot:jump_to_line(current_buf)
  end, {
    buffer = buf,
  })
end

function ot:render_outline()
  if self.status ~= nil and self.status then
    window.nvim_close_valid_window(self.winid)
    self.winid = 0
    self.status = false
    return
  end

  if not config.symbol_in_winbar.enable or not config.symbol_in_winbar.in_custom then
    do_symbol_request()
    return
  end

  self:update_outline()
end

return ot
