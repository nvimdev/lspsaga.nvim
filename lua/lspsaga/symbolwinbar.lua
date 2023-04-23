local lsp, api = vim.lsp, vim.api
local config = require('lspsaga').config.symbol_in_winbar
local libs = require('lspsaga.libs')
local symbar = {}

local cache = {}
symbar.__index = symbar

function symbar.__newindex(t, k, v)
  rawset(t, k, v)
end

local function bar_prefix()
  return {
    prefix = '%#SagaWinbar',
    sep = '%#SagaWinbarSep#' .. config.separator .. '%*',
  }
end

local function get_kind_icon(type, index)
  local kind = require('lspsaga.lspkind').get_kind()
  return kind[type][index]
end

local function respect_lsp_root(buf)
  local clients = lsp.get_active_clients({ bufnr = buf })
  if #clients == 0 then
    return
  end
  local root_dir = clients[1].config.root_dir
  local bufname = api.nvim_buf_get_name(buf)
  local bufname_parts = vim.split(bufname, libs.path_sep, { trimempty = true })
  if not root_dir then
    return { #bufname_parts }
  end
  local parts = vim.split(root_dir, libs.path_sep, { trimempty = true })
  return { unpack(bufname_parts, #parts + 1) }
end

local function bar_file_name(buf)
  local res
  if config.respect_root then
    res = respect_lsp_root(buf)
  end

  --fallback to config.folder_level
  if not res then
    res = libs.get_path_info(buf, config.folder_level)
  end

  if not res or #res == 0 then
    return
  end
  local data = libs.icon_from_devicon(vim.bo[buf].filetype, true)
  local bar = bar_prefix()
  local items = {}
  for i, v in pairs(res) do
    if i == #res then
      if #data > 0 then
        items[#items + 1] = '%#SagaWinbarFileIcon#' .. data[1] .. '%*'

        local ok, conf = pcall(api.nvim_get_hl_by_name, 'SagaWinbarFileIcon', true)
        if not ok then
          conf = {}
        end
        for k, _ in pairs(conf) do
          if type(k) ~= 'string' then
            conf[k] = nil
          end
        end

        api.nvim_set_hl(
          0,
          'SagaWinbarFileIcon',
          vim.tbl_extend('force', conf, {
            foreground = data[2],
          })
        )
      end
      items[#items + 1] = bar.prefix .. 'FileName#' .. v .. '%*'
    else
      items[#items + 1] = bar.prefix
        .. 'Folder#'
        .. get_kind_icon(302, 2)
        .. '%*'
        .. bar.prefix
        .. 'FolderName'
        .. '#'
        .. v
        .. '%*'
        .. bar.sep
    end
  end
  return table.concat(items, '')
end

local function get_node_range(node)
  if node.location then
    return node.location.range
  end

  if node.range then
    return node.range
  end
  return nil
end

--@private
local function binary_search(tbl, line)
  local left = 1
  local right = #tbl
  local mid = 0

  while true do
    mid = bit.rshift(left + right, 1)

    if mid == 0 then
      return nil
    end

    local range = get_node_range(tbl[mid])
    if not range then
      return nil
    end

    if line >= range.start.line and line <= range['end'].line then
      return mid
    elseif line < range.start.line then
      right = mid - 1
      if left > right then
        return nil
      end
    else
      left = mid + 1
      if left > right then
        return nil
      end
    end
  end
end

function symbar.node_is_keyword(buf, node)
  if not node.selectionRange then
    return false
  end

  if not vim.treesitter.get_captures_at_pos then
    return false
  end

  local captures = vim.treesitter.get_captures_at_pos(
    buf,
    node.selectionRange.start.line,
    node.selectionRange.start.character
  )
  for _, v in pairs(captures) do
    if v.capture == 'keyword' or v.capture == 'conditional' or v.capture == 'repeat' then
      return true
    end
  end
  return false
end

local function stl_escape(str)
  return str:gsub('%%', '')
end

local function insert_elements(buf, node, elements)
  if config.hide_keyword and symbar.node_is_keyword(buf, node) then
    return
  end
  local type = get_kind_icon(node.kind, 1)
  local icon = get_kind_icon(node.kind, 2)
  local bar = bar_prefix()
  if node.name:find('%%') then
    node.name = stl_escape(node.name)
  end

  if config.color_mode then
    local node_context = bar.prefix .. type .. '#' .. icon .. node.name
    elements[#elements + 1] = node_context
  else
    local node_context = bar.prefix
      .. type
      .. '#'
      .. icon
      .. bar.prefix
      .. 'Word'
      .. '#'
      .. node.name
    elements[#elements + 1] = node_context
  end
end

--@private
local function find_in_node(buf, tbl, line, elements)
  local mid = binary_search(tbl, line)
  if mid == nil then
    return
  end

  local node = tbl[mid]

  local range = get_node_range(tbl[mid]) or {}

  if mid > 1 then
    for i = 1, mid - 1 do
      local prev_range = get_node_range(tbl[i]) or {}
      if -- not sure there should be 6 or other kind can be used in here
        tbl[i].kind == 6
        and range.start.line > prev_range.start.line
        and range['end'].line <= prev_range['end'].line
      then
        insert_elements(buf, tbl[i], elements)
      end
    end
  end

  insert_elements(buf, tbl[mid], elements)

  if node.children ~= nil and next(node.children) ~= nil then
    find_in_node(buf, node.children, line, elements)
  end
end

--@private
local render_symbol_winbar = function(buf, symbols)
  local cur_buf = api.nvim_get_current_buf()
  if cur_buf ~= buf then
    return
  end

  -- don't show in float window.
  local cur_win = api.nvim_get_current_win()
  local winconf = api.nvim_win_get_config(cur_win)
  if #winconf.relative > 0 then
    return
  end

  local current_line = api.nvim_win_get_cursor(cur_win)[1]
  local winbar_str = config.show_file and bar_file_name(buf) or ''

  local winbar_elements = {}

  find_in_node(buf, symbols, current_line - 1, winbar_elements)

  local lens, over_idx = 0, 0
  local max_width = math.floor(api.nvim_win_get_width(cur_win) * 0.9)
  for i, item in pairs(winbar_elements) do
    local s = vim.split(item, '#')
    lens = lens + api.nvim_strwidth(s[3]) + api.nvim_strwidth(config.separator)
    if lens > max_width then
      over_idx = i
      lens = 0
    end
  end

  if over_idx > 0 then
    winbar_elements = { unpack(winbar_elements, over_idx) }
    table.insert(winbar_elements, 1, '...')
  end

  local bar = bar_prefix()
  local str = table.concat(winbar_elements, bar.sep)

  if config.show_file and next(winbar_elements) ~= nil then
    str = bar.sep .. str
  end

  winbar_str = winbar_str .. str

  if config.enable and api.nvim_win_get_height(cur_win) - 1 > 1 then
    if #winbar_str == 0 then
      winbar_str = bar_prefix().prefix .. ' #'
    end
    api.nvim_set_option_value('winbar', winbar_str, { scope = 'local', win = cur_win })
  end
  return winbar_str
end

--- Get buffer symbols from cache
---@private
local function get_buf_symbol(buf)
  buf = buf or api.nvim_get_current_buf()
  local res = {}

  if not cache[buf] then
    return res
  end

  if cache[buf].pending_request then
    res.pending_request = cache[buf].pending_request
    return res
  end

  res.symbols = cache[buf].symbols
  res.pending_request = cache[buf].pending_request
  return res
end

function symbar:do_symbol_request(buf, callback)
  local params = { textDocument = lsp.util.make_text_document_params() }

  local client = libs.get_client_by_cap('documentSymbolProvider')
  if not client then
    return
  end
  self[buf].pending_request = true
  client.request('textDocument/documentSymbol', params, callback, buf)
end

function symbar:refresh_symbol_cache(buf, render_fn)
  local function handler(_, result, ctx)
    if api.nvim_get_current_buf() ~= buf or not self[ctx.bufnr] then
      return
    end

    self[ctx.bufnr].pending_request = false
    if not result then
      return
    end

    if render_fn then
      render_fn(buf, result)
    end

    self[ctx.bufnr].symbols = result
  end
  self:do_symbol_request(buf, handler)
end

function symbar:init_buf_symbols(buf, render_fn)
  local res = get_buf_symbol(buf)
  if res.pending_request then
    return
  end

  if not res.symbols or (next(res.symbols) == nil and not res.pending_request) then
    self:refresh_symbol_cache(buf, render_fn)
  else
    render_fn(buf, res.symbols)
  end
end

local function clean_buf_cache(buf)
  buf = buf or api.nvim_get_current_buf()
  if buf and cache[buf] then
    for k, _ in pairs(cache[buf]) do
      cache[buf][k] = nil
    end
    cache[buf] = nil
  end
end

function symbar:register_events(buf)
  local augroup = api.nvim_create_augroup('LspsagaSymbol' .. tostring(buf), { clear = true })
  self[buf].group = augroup

  api.nvim_create_autocmd('CursorMoved', {
    group = augroup,
    buffer = buf,
    callback = function()
      self:init_buf_symbols(buf, render_symbol_winbar)
    end,
    desc = 'Lspsaga symbols render and request',
  })

  api.nvim_create_autocmd('InsertLeave', {
    group = augroup,
    buffer = buf,
    callback = function()
      if not config.enable then
        self:refresh_symbol_cache(buf, render_symbol_winbar)
      else
        self:refresh_symbol_cache(buf)
      end
    end,
    desc = 'Lspsaga update symbols',
  })

  api.nvim_buf_attach(buf, false, {
    on_detach = function()
      if self[buf] and self[buf].group then
        pcall(api.nvim_del_augroup_by_id, self[buf].group)
      end
      clean_buf_cache(buf)
    end,
  })
end

local function match_ignore(buf)
  local fname = api.nvim_buf_get_name(buf)
  for _, pattern in pairs(config.ignore_patterns) do
    if fname:find(pattern) then
      return true
    end
  end
  return false
end

function symbar:symbol_autocmd()
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('LspsagaSymbols', { clear = false }),
    callback = function(opt)
      if vim.bo[opt.buf].buftype == 'nofile' then
        return
      end

      local winid = api.nvim_get_current_win()
      if api.nvim_get_current_buf() ~= opt.buf then
        return
      end

      local ok, _ = pcall(api.nvim_win_get_var, winid, 'disable_winbar')
      if ok then
        return
      end

      if config.show_file then
        api.nvim_set_option_value(
          'winbar',
          bar_file_name(opt.buf),
          { scope = 'local', win = winid }
        )
      else
        api.nvim_set_option_value(
          'winbar',
          bar_prefix().prefix .. ' #',
          { scope = 'local', win = winid }
        )
      end

      --ignored after folder file prefix set
      if match_ignore(opt.buf) then
        return
      end

      if not self[opt.buf] then
        self[opt.buf] = {}
      end

      self:init_buf_symbols(opt.buf, render_symbol_winbar)
      self:register_events(opt.buf)
    end,
    desc = 'Lspsaga get and show symbols',
  })
end

---Get buffer symbols
---@return  string | nil
function symbar:get_winbar()
  local buf = api.nvim_get_current_buf()
  if not self[buf] then
    self[buf] = {}
  end

  local res = get_buf_symbol(buf)
  if vim.tbl_isempty(res) or not res.symbols then
    self:refresh_symbol_cache(buf)
    return
  end

  if res.pending_request then
    return
  end

  self:register_events(buf)

  if res.symbols then
    return render_symbol_winbar(buf, res.symbols)
  end
end

return setmetatable(cache, symbar)
