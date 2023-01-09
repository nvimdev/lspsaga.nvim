local ot = {}
local api, lsp, fn, keymap = vim.api, vim.lsp, vim.fn, vim.keymap
local config = require('lspsaga').config
local libs = require('lspsaga.libs')
local symbar = require('lspsaga.symbolwinbar')
local outline_conf, ui = config.outline, config.ui
local insert = table.insert

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
end

local virt_id = api.nvim_create_namespace('lspsaga_outline')

local function get_hi_prefix()
  return 'LSOutline'
end

local function get_kind()
  return require('lspsaga.highlight').get_kind()
end

local function ignore_kind()
  return {}
end

local function parse_symbols(buf, symbols)
  local res = {}
  local kind = get_kind()

  local tmp_node = function(node)
    local tmp = {}
    tmp.type = kind[node.kind][1]
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
  table.sort(keys)
  local new = {}
  for _, v in pairs(keys) do
    new[v] = res[v]
  end
  return new
end

function ot:expand_collaspe() end

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

---@private
local function request_and_render(buf, render_fn)
  local params = { textDocument = lsp.util.make_text_document_params(buf) }
  local client = libs.get_client_by_cap('documentSymbolProvider')

  if not client then
    return
  end

  client.request('textDocument/documentSymbol', params, function(_, result)
    if not result or next(result) == nil then
      return
    end
    if render_fn then
      render_fn(result)
    end
  end, buf)
end

local function render_outline(buf, symbols)
  local curbuf = api.nvim_get_current_buf()
  if curbuf ~= buf then
    return
  end
  ot.winid, ot.bufnr = create_outline_window()
  local res = parse_symbols(buf, symbols)
  local lines = {}
  local kind = get_kind()
  local fname = libs.get_path_info(buf, 1)
  local data = libs.icon_from_devicon(vim.bo[buf].filetype)
  ---@diagnostic disable-next-line: need-check-nil
  insert(lines, ' ' .. data[1] .. ' ' .. fname[1])
  local prefix = get_hi_prefix()
  local hi = {}
  for k, v in pairs(res) do
    if #v.data > 0 then
      local scope = {}
      local indent_with_icon = '  ' .. config.ui.collaspe
      insert(lines, indent_with_icon .. ' ' .. kind[k][1])
      scope['SagaCollaspe'] = { 0, #indent_with_icon }
      scope[prefix .. kind[k][1]] = { #indent_with_icon, -1 }
      insert(hi, scope)
      for j, node in pairs(v.data) do
        local c_scope = {}
        local indent = j == #v.data and '  └' .. '─' or '  ├' .. '─'
        insert(lines, indent .. kind[node.kind][2] .. node.name)
        c_scope['OutlineIndent'] = { 0, #indent }
        c_scope[prefix .. kind[node.kind][1]] = { #indent, #indent + #kind[node.kind][2] }
        insert(hi, c_scope)
      end
      table.insert(lines, '')
      table.insert(hi, {})
    end
  end
  api.nvim_buf_set_lines(ot.bufnr, 0, -1, false, lines)
  api.nvim_buf_add_highlight(ot.bufnr, 0, data[2], 0, 0, 4)
  for k, v in pairs(hi) do
    if not vim.tbl_isempty(v) then
      for group, scope in pairs(v) do
        api.nvim_buf_add_highlight(ot.bufnr, 0, group, k, scope[1], scope[2])
      end
    end
  end
end

function ot:close_when_last()
  api.nvim_create_autocmd('BufEnter', {
    callback = function(opt)
      local wins = api.nvim_list_wins()
      if #wins == 1 and vim.bo[opt.buf].filetype == 'lspsagaoutline' then
        api.nvim_buf_delete(self.bufnr, { force = true })
        local bufnr = api.nvim_create_buf(true, true)
        api.nvim_win_set_buf(0, bufnr)
        self.winid = nil
        self.bufnr = nil
        for k, _ in pairs(self) do
          if type(k) == 'table' then
            self[k] = nil
          end
        end
        api.nvim_del_autocmd(opt.id)
      end
    end,
    desc = 'Outline auto close when last one',
  })
end

function ot:outline()
  local current_buf = api.nvim_get_current_buf()
  if not self[current_buf] then
    self[current_buf] = {}
  end
  local symbols = get_cache_symbols(current_buf)
  if not symbols then
    request_and_render(current_buf, render_outline)
    return
  end
  render_outline(current_buf, symbols)
end

return ot
