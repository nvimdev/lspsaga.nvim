local window = require('lspsaga.window')
local kind = require('lspsaga.lspkind')
local api, lsp, fn, co = vim.api, vim.lsp, vim.fn, coroutine
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')
local scroll_in_win = require('lspsaga.action').scroll_in_win
local saga_augroup = require('lspsaga').saga_augroup
local symbar = require('lspsaga.symbolwinbar')
local path_sep = libs.path_sep
local icons = config.finder_icons

local methods = { 'textDocument/definition', 'textDocument/references' }

local do_request = co.create(function(method)
  local timeout = 1000
  local msgs = {
    [methods[1]] = '0 Definitions Found',
    [methods[2]] = '0 References  Found',
  }

  while true do
    local win = api.nvim_get_current_win()
    local bufnr = api.nvim_win_get_buf(win)
    local params = lsp.util.make_position_params()
    if method == methods[2] then
      params.context = { includeDeclaration = true }
    end

    local resp = lsp.buf_request_sync(bufnr, method, params, timeout)
    if libs.result_isempty(resp) then
      resp = {}
      resp.result = { {
        saga_msg = msgs[method],
      } }
    end

    local results = {}
    for _, res in pairs(resp) do
      if res.result and next(res.result) ~= nil then
        for _, v in pairs(res.result) do
          table.insert(results, v)
        end
      end
    end

    method = coroutine.yield(results)
  end
end)

local Finder = {}

function Finder:word_symbol_kind()
  local current_buf = api.nvim_get_current_buf()
  local current_word = vim.fn.expand('<cword>')

  local clients = vim.lsp.buf_get_clients()
  local client
  for client_id, conf in pairs(clients) do
    if conf.server_capabilities.documentHighlightProvider then
      client = client_id
    end
  end

  local result = {}

  if symbar.symbol_cache[current_buf] ~= nil then
    result = symbar.symbol_cache[current_buf][2]
  else
    local method = 'textDocument/documentSymbol'
    if client ~= nil then
      local params = { textDocument = lsp.util.make_text_document_params() }
      local results = lsp.buf_request_sync(current_buf, method, params, 500)
      if results ~= nil then
        result = results[client].result
      end
    else
      vim.notify('All Servers of this buffer not support ' .. method)
    end
  end

  local index = 0
  if next(result) ~= nil then
    for i, val in pairs(result) do
      if val.name:find(current_word) then
        index = i
        break
      end
    end
  end

  local icon = index ~= 0 and kind[result[index].kind][2] or ' '
  self.param = icon .. current_word
end

function Finder:lsp_finder_request()
  local root_dir = libs.get_lsp_root_dir()
  if string.len(root_dir) == 0 then
    vim.notify('[LspSaga] get root dir failed')
    return
  end
  -- get current word symbol kind
  self:word_symbol_kind()

  self.WIN_WIDTH = fn.winwidth(0)
  self.WIN_HEIGHT = fn.winheight(0)
  self.contents = {}
  self.short_link = {}
  self.definition_uri = 0
  self.reference_uri = 0
  self.buf_filetype = api.nvim_buf_get_option(0, 'filetype')

  for _, method in pairs(methods) do
    local ok, result = co.resume(do_request, method)
    if not ok then
      vim.notify('Wrong response in do_request coroutine')
    end
    self:create_finder_contents(result, method, root_dir)
  end
  self:render_finder_result()
end

function Finder:create_finder_contents(result, method, root_dir)
  local target_lnum = 0
  local titles = {
    [methods[1]] = icons.define .. 'Definitions ' .. #result .. ' results',
    [methods[2]] = icons.ref .. 'References  ' .. #result .. ' results',
  }

  if method == methods[1] then
    self.definition_uri = result.saga_msg and 1 or #result
    table.insert(self.contents, titles[method])
    target_lnum = 2
    if result.saga_msg then
      table.insert(self.contents, ' ')
      table.insert(self.contents, '[1] ' .. result.saga_msg)
      return
    end
  else
    self.reference_uri = result.saga_msg and 1 or #result
    target_lnum = target_lnum + self.definition_uri + 5
    table.insert(self.contents, ' ')
    table.insert(self.contents, titles[method])
    if result.saga_msg then
      table.insert(self.contents, ' ')
      table.insert(self.contents, '[1] ' .. result.saga_msg)
      return
    end
  end

  for index, _ in ipairs(result) do
    local uri = result[index].targetUri or result[index].uri
    if uri == nil then
      return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    if not api.nvim_buf_is_loaded(bufnr) then
      fn.bufload(bufnr)
    end
    local link = vim.uri_to_fname(uri) -- returns lowercase drive letters on Windows
    if libs.is_windows() then
      link = link:gsub('^%l', link:sub(1, 1):upper())
    end
    local short_name

    -- reduce filename length by root_dir or home dir
    if link:find(root_dir, 1, true) then
      short_name = link:sub(root_dir:len() + 2)
    else
      local _split = vim.split(link, path_sep)
      if #_split > 5 then
        short_name = table.concat(_split, path_sep, #_split - 2, #_split)
      end
    end

    local target_line = icons.link .. short_name
    local range = result[index].targetRange or result[index].range
    if index == 1 then
      table.insert(self.contents, ' ')
    end
    table.insert(self.contents, target_line)
    target_lnum = target_lnum + 1
    -- max_preview_lines
    local max_preview_lines = config.max_preview_lines
    local lines = api.nvim_buf_get_lines(bufnr, range.start.line - 0, range['end'].line + 1 + max_preview_lines, false)

    self.short_link[target_lnum] = {
      link = link,
      preview = lines,
      row = range.start.line + 1,
      col = range.start.character + 1,
    }
  end
end

function Finder:render_finder_result()
  if next(self.contents) == nil then
    return
  end
  table.insert(self.contents, ' ')
  -- get dimensions
  local width = api.nvim_get_option('columns')
  local height = api.nvim_get_option('lines')

  -- calculate our floating window size
  local win_height = math.ceil(height * 0.8)
  local win_width = math.ceil(width * 0.8)

  -- and its starting position
  local row = math.ceil((height - win_height) * 0.7)
  local col = math.ceil((width - win_width))
  local opts = {
    style = 'minimal',
    relative = 'editor',
    row = row,
    col = col,
  }

  local max_height = math.ceil((height - 4) * 0.5)
  if #self.contents > max_height then
    opts.height = max_height
  end

  local content_opts = {
    contents = self.contents,
    filetype = 'lspsagafinder',
    enter = true,
    highlight = 'LspSagaLspFinderBorder',
  }

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
  api.nvim_buf_set_option(self.bufnr, 'buflisted', false)
  api.nvim_win_set_var(self.winid, 'lsp_finder_win_opts', opts)
  api.nvim_win_set_option(self.winid, 'cursorline', true)

  if vim.v.version >= 800 then
    -- create winbar of finder
    local prefix = '%#LSFinderBarFind# Find: %*'
    local titlebr = '%#LSFinderBarParam#' .. self.param .. ' %*'
    opts.row = opts.row - 1
    opts.col = opts.col + 1
    self.titlebar_bufnr, self.titlebar_winid = window.create_win_with_border({
      contents = { '                     ', '' },
      filetype = 'lspsagafindertitlebar',
      border = 'none',
    }, opts)

    api.nvim_win_set_option(self.titlebar_winid, 'winbar', prefix .. titlebr)
  end

  self:get_cursorline_highlight()

  api.nvim_set_hl(0, 'CursorLine', { link = 'LspSagaFinderSelection' })

  api.nvim_create_autocmd('CursorMoved', {
    group = saga_augroup,
    buffer = self.bufnr,
    callback = function()
      require('lspsaga.finder'):set_cursor()
    end,
  })
  api.nvim_create_autocmd('CursorMoved', {
    group = saga_augroup,
    buffer = self.bufnr,
    callback = function()
      require('lspsaga.finder'):auto_open_preview()
    end,
  })
  api.nvim_create_autocmd('QuitPre', {
    group = saga_augroup,
    buffer = self.bufnr,
    callback = function()
      require('lspsaga.finder'):quit_float_window()
    end,
  })

  for i = 1, self.definition_uri, 1 do
    api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', 1 + i, 0, -1)
  end

  for i = 1, self.reference_uri, 1 do
    local def_count = self.definition_uri ~= 0 and self.definition_uri or -1
    api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', i + def_count + 4, 0, -1)
  end
  -- disable some move keys in finder window
  libs.disable_move_keys(self.bufnr)
  -- load float window map
  self:apply_float_map()
  self:lsp_finder_highlight()
end

function Finder:apply_float_map()
  local action = config.finder_action_keys
  local move = config.move_in_saga
  local nvim_create_keymap = require('lspsaga.libs').nvim_create_keymap
  local lhs = {
    noremap = true,
    silent = true,
  }
  local keymaps = {
    { self.bufnr, 'n', move.prev, '<Up>' },
    { self.bufnr, 'n', move.next, '<Down>' },
    { self.bufnr, 'n', action.vsplit, ":lua require('lspsaga.finder'):open_link(2)<CR>" },
    { self.bufnr, 'n', action.split, ":lua require('lspsaga.finder'):open_link(3)<CR>" },
    { self.bufnr, 'n', action.scroll_down, ":lua require('lspsaga.finder'):scroll_in_preview(1)<CR>" },
    { self.bufnr, 'n', action.scroll_up, ":lua require('lspsaga.finder'):scroll_in_preview(-1)<CR>" },
  }

  if type(action.open) == 'table' then
    for _, key in ipairs(action.open) do
      table.insert(keymaps, { self.bufnr, 'n', key, ":lua require('lspsaga.finder'):open_link(1)<CR>" })
    end
  elseif type(action.open) == 'string' then
    table.insert(keymaps, { self.bufnr, 'n', action.open, ":lua require('lspsaga.finder'):open_link(1)<CR>" })
  end

  if type(action.quit) == 'table' then
    for _, key in ipairs(action.quit) do
      table.insert(keymaps, { self.bufnr, 'n', key, ":lua require('lspsaga.finder'):quit_float_window()<CR>" })
    end
  elseif type(action.quit) == 'string' then
    table.insert(keymaps, { self.bufnr, 'n', action.quit, ":lua require('lspsaga.finder'):quit_float_window()<CR>" })
  end
  nvim_create_keymap(keymaps, lhs)
end

function Finder:lsp_finder_highlight()
  local def_uri_count = self.definition_uri == 0 and -1 or self.definition_uri
  local def_len = string.len('Definitions')
  local ref_len = string.len('References')
  -- add syntax
  api.nvim_buf_add_highlight(self.bufnr, -1, 'DefinitionsIcon', 0, 0, #icons.define)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'Definitions', 0, #icons.define, #icons.define + def_len)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'DefinitionCount', 0, #icons.define + def_len, -1)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'ReferencesIcon', 3 + def_uri_count, 0, #icons.ref)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'References', 3 + def_uri_count, #icons.ref, #icons.ref + ref_len)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'ReferencesCount', 3 + def_uri_count, #icons.ref + ref_len, -1)
end

function Finder:set_cursor()
  local current_line = fn.line('.')
  local column = #icons.link + 1

  local first_def_uri_lnum = self.definition_uri ~= 0 and 3 or 5
  local last_def_uri_lnum = 3 + self.definition_uri - 1
  local first_ref_uri_lnum = 3 + self.definition_uri + 3
  local count = self.definition_uri == 0 and 1 or 2
  local last_ref_uri_lnum = 3 + self.definition_uri + count + self.reference_uri

  if current_line == 1 then
    fn.cursor(first_def_uri_lnum, column)
  elseif current_line == last_def_uri_lnum + 1 then
    fn.cursor(first_ref_uri_lnum, column)
  elseif current_line == last_ref_uri_lnum + 1 then
    fn.cursor(first_def_uri_lnum, column)
  elseif current_line == first_ref_uri_lnum - 1 then
    if self.definition_uri == 0 then
      fn.cursor(first_def_uri_lnum, column)
    else
      fn.cursor(last_def_uri_lnum, column)
    end
  elseif current_line == first_def_uri_lnum - 1 then
    fn.cursor(last_ref_uri_lnum, column)
  end
end

function Finder:get_cursorline_highlight()
  self.cursorline_color = api.nvim_get_hl_by_name('Cursorline', true)
end

function Finder:auto_open_preview()
  local current_line = fn.line('.')
  if not self.short_link[current_line] then
    return
  end
  local content = self.short_link[current_line].preview or {}

  if next(content) ~= nil then
    local has_var, finder_win_opts = pcall(api.nvim_win_get_var, 0, 'lsp_finder_win_opts')
    if not has_var then
      vim.notify('get finder window options wrong')
      return
    end
    local opts = {
      relative = 'editor',
      -- We'll make sure the preview window is the correct size
      no_size_override = true,
    }

    local finder_width = fn.winwidth(0)
    local finder_height = fn.winheight(0)
    local screen_width = api.nvim_get_option('columns')

    local content_width = 0
    for _, line in ipairs(content) do
      content_width = math.max(fn.strdisplaywidth(line), content_width)
    end

    local border_width
    if config.border_style == 'double' then
      border_width = 4
    else
      border_width = 2
    end

    local max_width = screen_width - finder_win_opts.col - finder_width - border_width - 2

    if max_width > 42 then
      -- Put preview window to the right of the finder window
      local preview_width = math.min(content_width + border_width, max_width)
      opts.col = finder_win_opts.col + finder_width + 2
      opts.row = finder_win_opts.row
      opts.width = preview_width
      opts.height = self.definition_uri + self.reference_uri + 6
      if opts.height > finder_height then
        opts.height = finder_height
      end
    else
      -- Put preview window below the finder window
      local max_height = self.WIN_HEIGHT - finder_win_opts.row - finder_height - border_width - 2
      if max_height <= 3 then
        return
      end -- Don't show preview window if too short

      opts.row = finder_win_opts.row + finder_height + 2
      opts.col = finder_win_opts.col
      opts.width = finder_width
      opts.height = math.min(8, max_height)
    end

    local content_opts = {
      contents = content,
      filetype = self.buf_filetype,
      highlight = 'LspSagaAutoPreview',
    }

    vim.defer_fn(function()
      self:close_auto_preview_win()
      local bufnr, winid = window.create_win_with_border(content_opts, opts)
      api.nvim_buf_set_option(bufnr, 'buflisted', false)
      local last_lnum = #content > config.max_preview_lines and config.max_preview_lines or #content
      api.nvim_win_set_var(0, 'saga_finder_preview', { winid, 1, last_lnum })
    end, 5)
  end
end

function Finder:close_auto_preview_win()
  local has_var, pdata = pcall(api.nvim_win_get_var, 0, 'saga_finder_preview')
  if has_var then
    window.nvim_close_valid_window(pdata[1])
  end
end

-- action 1 mean enter
-- action 2 mean vsplit
-- action 3 mean split
-- action 4 mean tabe
function Finder:open_link(action_type)
  local action = { 'edit ', 'vsplit ', 'split ', 'tabe ' }
  local current_line = fn.line('.')

  if self.short_link[current_line] == nil then
    error('[LspSaga] target file uri not exist')
    return
  end

  self:close_auto_preview_win()
  api.nvim_win_close(self.winid, true)
  api.nvim_command(action[action_type] .. self.short_link[current_line].link)
  fn.cursor(self.short_link[current_line].row, self.short_link[current_line].col)
  self:clear_tmp_data()
end

function Finder:scroll_in_preview(direction)
  local has_var, pdata = pcall(api.nvim_win_get_var, 0, 'saga_finder_preview')
  if not has_var then
    return
  end
  if not api.nvim_win_is_valid(pdata[1]) then
    return
  end

  local current_win_lnum, last_lnum = pdata[2], pdata[3]
  current_win_lnum = scroll_in_win(pdata[1], direction, current_win_lnum, last_lnum, config.max_preview_lines)
  api.nvim_win_set_var(0, 'saga_finder_preview', { pdata[1], current_win_lnum, last_lnum })
end

function Finder:quit_float_window()
  self:close_auto_preview_win()
  if self.winid ~= 0 then
    window.nvim_close_valid_window(self.winid)
    if vim.v.version >= 800 then
      window.nvim_close_valid_window(self.titlebar_winid)
    end
  end

  self:clear_tmp_data()
end

function Finder:clear_tmp_data()
  self.short_link = {}
  self.contents = {}
  self.definition_uri = 0
  self.reference_uri = 0
  self.param_length = 0
  self.buf_filetype = ''
  self.WIN_HEIGHT = 0
  self.WIN_WIDTH = 0
  api.nvim_set_hl(0, 'CursorLine', self.cursorline_color)
end

function Finder.lsp_finder()
  if not libs.check_lsp_active() then
    return
  end

  Finder:lsp_finder_request()
end

return Finder
