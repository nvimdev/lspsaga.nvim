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
local insert = table.insert
local uv = vim.loop
local indent = '    '

local methods = { 'textDocument/definition', 'textDocument/references' }
local msgs = {
  [methods[1]] = 'No Definitions Found',
  [methods[2]] = 'No References  Found',
}

local symbol_method = 'textDocument/documentSymbol'

local Finder = {}

function Finder:lsp_finder()
  if not libs.check_lsp_active() then
    return
  end

  self:word_symbol_kind()
  local params = lsp.util.make_position_params()
  for _, method in pairs(methods) do
    self:do_request(params, method)
  end

  self:get_file_icon()
  -- make a spinner
  self:wait_spinner()
end

function Finder:wait_spinner()
  self.WIN_WIDTH = fn.winwidth(0)
  self.WIN_HEIGHT = fn.winheight(0)

  -- calculate our floating window size
  local win_height = math.ceil(self.WIN_HEIGHT * 0.6)
  local win_width = math.ceil(self.WIN_WIDTH * 0.8)

  -- and its starting position
  local row = math.ceil((self.WIN_HEIGHT - win_height) / 2 - 1)
  local col = math.ceil(self.WIN_WIDTH - win_width)

  local opts = {
    relative = 'editor',
    height = 2,
    width = 20,
    row = row,
    col = col,
  }

  local content_opts = {
    contents = {},
    highlight = 'FinderSpinnerBorder',
    enter = false,
  }

  self.spin_buf, self.spin_win = window.create_win_with_border(content_opts, opts)
  local spin_config = {
    spinner = {
      '█▁▁▁▁▁▁▁▁▁',
      '██▁▁▁▁▁▁▁▁',
      '███▁▁▁▁▁▁▁',
      '████▁▁▁▁▁▁',
      '█████▁▁▁▁▁',
      '██████▁▁▁▁',
      '███████▁▁▁',
      '████████▁▁ ',
      '█████████▁',
      '██████████',
    },
    interval = 10,
    timeout = config.finder_request_timeout,
  }
  api.nvim_buf_set_option(self.spin_buf, 'modifiable', true)

  self.request_status = {
    [methods[1]] = false,
    [methods[2]] = false,
  }

  local spin_frame = 1
  self.spin_timer = uv.new_timer()
  local start_request = uv.now()
  self.spin_timer:start(
    0,
    spin_config.interval,
    vim.schedule_wrap(function()
      for _, method in pairs(methods) do
        if self.request_result[method] then
          self.request_status[method] = true
        end
      end

      spin_frame = spin_frame == 11 and 1 or spin_frame
      local msg = ' LOADING' .. string.rep('.', spin_frame > 3 and 3 or spin_frame)
      local spinner = ' ' .. spin_config.spinner[spin_frame]
      api.nvim_buf_set_lines(self.spin_buf, 0, -1, false, { msg, spinner })
      api.nvim_buf_add_highlight(self.spin_buf, 0, 'FinderSpinnerTitle', 0, 0, -1)
      api.nvim_buf_add_highlight(self.spin_buf, 0, 'FinderSpinner', 1, 0, -1)
      spin_frame = spin_frame + 1

      if uv.now() - start_request >= spin_config.timeout and not self.spin_timer:is_closing() then
        self.spin_timer:stop()
        self.spin_timer:close()
        window.nvim_close_valid_window(self.spin_win)
        vim.notify('request timeout')
        self.spin_win = nil
        return
      end

      if
        (self.request_status[methods[1]] or self.request_status[methods[2]])
        and not self.spin_timer:is_closing() and self.param ~= nil
      then
        self.spin_timer:stop()
        self.spin_timer:close()
        window.nvim_close_valid_window(self.spin_win)
        self.spin_win = nil
        self:lsp_finder_request()
      end
    end)
  )
end

function Finder:do_request(params, method)
  if method == methods[2] then
    params.context = { includeDeclaration = true }
  end
  self.client.request(method, params, function(_, result)
    self.request_result[method] = result
  end, self.current_buf)
end

function Finder:word_symbol_kind()
  self.current_buf = api.nvim_get_current_buf()
  self.request_result = {}
  local current_word = vim.fn.expand('<cword>')

  local caps = { 'documentSymbolProvider', 'referencesProvider', 'definitionProvider' }
  self.client = libs.get_client_by_cap(caps)
  local result = {}

  local param_with_icon = function()
    local index = 0
    if result ~= nil and next(result) ~= nil then
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

  if symbar.symbol_cache[self.current_buf] ~= nil then
    result = symbar.symbol_cache[self.current_buf][2]
    param_with_icon()
    return
  else
    if self.client ~= nil then
      local params = { textDocument = lsp.util.make_text_document_params() }
      self.client.request(symbol_method, params, function(_, results)
        if results ~= nil then
          result = results
        end
        param_with_icon()
      end, self.current_buf)
      return
    end
  end
  vim.notify('All Servers of this buffer not support ' .. symbol_method)
end

function Finder:get_file_icon()
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  self.f_icon = ''
  self.f_hl = ''
  if ok then
    self.f_icon, self.f_hl = devicons.get_icon_by_filetype(vim.bo.filetype)
  end
  -- if filetype doesn't match devicon will set f_icon to nil so add a patch
  self.f_icon = self.f_icon == nil and '' or (self.f_icon .. ' ')
  self.f_hl = self.f_hl == nil and '' or self.f_hl
end

function Finder:lsp_finder_request()
  local root_dir = libs.get_lsp_root_dir()
  if string.len(root_dir) == 0 then
    vim.notify('[LspSaga] get root dir failed')
    return
  end

  self.contents = {}
  self.short_link = {}
  self.definition_uri = 0
  self.reference_uri = 0
  self.buf_filetype = api.nvim_buf_get_option(0, 'filetype')

  self:create_finder_contents(self.request_result[methods[1]] or {}, methods[1], root_dir)
  self:create_finder_contents(self.request_result[methods[2]] or {}, methods[2], root_dir)
  self:render_finder_result()
end

function Finder:create_finder_contents(result, method, root_dir)
  local target_lnum = 0
  -- remove definition in references
  if self.short_link ~= nil and self.short_link[3] ~= nil and next(result) ~= nil then
    local start = result[1].range.start
    if
      start.line == self.short_link[3].row - 1 and start.character == self.short_link[3].col - 1
    then
      table.remove(result, 1)
    end
  end

  local titles = {
    [methods[1]] = icons.def .. 'Definition ' .. #result .. ' results',
    [methods[2]] = icons.ref .. 'References ' .. #result .. ' results',
  }

  if method == methods[1] then
    self.definition_uri = #result == 0 and 1 or #result
    insert(self.contents, titles[method])
    target_lnum = 2
    if #result == 0 then
      insert(self.contents, ' ')
      insert(self.contents, indent .. self.f_icon .. msgs[method])
      return
    end
  else
    self.reference_uri = #result == 0 and 1 or #result
    target_lnum = target_lnum + self.definition_uri + 5
    insert(self.contents, ' ')
    insert(self.contents, titles[method])
    if #result == 0 then
      insert(self.contents, ' ')
      insert(self.contents, indent .. self.f_icon .. msgs[method])
      return
    end
  end

  for index, res in ipairs(result) do
    local uri = res.targetUri or res.uri
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

    local target_line = indent .. self.f_icon .. short_name
    local range = res.targetRange or res.range
    if index == 1 then
      insert(self.contents, ' ')
    end
    insert(self.contents, target_line)
    target_lnum = target_lnum + 1
    -- max_preview_lines
    local max_preview_lines = config.max_preview_lines
    local lines = api.nvim_buf_get_lines(
      bufnr,
      range.start.line - 0,
      range['end'].line + 1 + max_preview_lines,
      false
    )

    self.short_link[target_lnum] = {
      link = link,
      preview = lines,
      row = range.start.line + 1,
      col = range.start.character + 1,
    }
  end
end

local ns_id = api.nvim_create_namespace('lspsagafinder')

function Finder:render_finder_result()
  if next(self.contents) == nil then
    return
  end
  insert(self.contents, ' ')
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
  api.nvim_win_set_option(self.winid, 'cursorline', false)

  opts.row = opts.row - 1
  opts.col = opts.col + 1
  opts.width = #self.param + 8
  opts.height = 2
  opts.no_size_override = true
  self.titlebar_bufnr, self.titlebar_winid = window.create_win_with_border({
    contents = { string.rep(' ', #self.param + 12), '' },
    filetype = 'lspsagafindertitlebar',
    border = 'none',
  }, opts)

  local titlebar_ns = api.nvim_create_namespace('FinderTitleBar')
  api.nvim_buf_set_extmark(self.titlebar_bufnr, titlebar_ns, 0, 0, {
    virt_text = { { 'Find: ' .. self.param, 'FinderParam' } },
    virt_text_pos = 'overlay',
    virt_lines_above = false,
  })

  api.nvim_create_autocmd('CursorMoved', {
    group = saga_augroup,
    buffer = self.bufnr,
    callback = function()
      self:set_cursor()
      self:auto_open_preview()
    end,
  })

  api.nvim_create_autocmd('QuitPre', {
    group = saga_augroup,
    buffer = self.bufnr,
    callback = function()
      self:quit_float_window()
    end,
  })

  local virt_hi = 'FinderVirtText'

  api.nvim_buf_set_extmark(0, ns_id, 1, 0, {
    virt_text = { { '│', virt_hi } },
    virt_text_pos = 'overlay',
  })

  for i = 1, self.definition_uri, 1 do
    local virt_texts = {}
    api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', 1 + i, 0, -1)
    api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, 1 + i, 0, #indent + #self.f_icon)

    if i == self.definition_uri then
      insert(virt_texts, { '└', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    else
      insert(virt_texts, { '├', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    end

    api.nvim_buf_set_extmark(0, ns_id, i + 1, 0, {
      virt_text = virt_texts,
      virt_text_pos = 'overlay',
    })
  end

  api.nvim_buf_set_extmark(0, ns_id, 4 + self.definition_uri, 0, {
    virt_text = { { '│', virt_hi } },
    virt_text_pos = 'overlay',
  })

  for i = 1, self.reference_uri, 1 do
    local virt_texts = {}
    api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', 1 + i, 0, -1)
    local def_count = self.definition_uri ~= 0 and self.definition_uri or -1
    api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', i + def_count + 4, 0, -1)
    api.nvim_buf_add_highlight(
      self.bufnr,
      -1,
      self.f_hl,
      i + def_count + 4,
      0,
      #indent + #self.f_icon
    )

    if i == self.reference_uri then
      insert(virt_texts, { '└', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    else
      insert(virt_texts, { '├', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    end

    api.nvim_buf_set_extmark(0, ns_id, i + def_count + 4, 0, {
      virt_text = virt_texts,
      virt_text_pos = 'overlay',
    })
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
  local opts = {
    buffer = self.bufnr,
    noremap = true,
    silent = true,
  }

  local open_func = function()
    self:open_link(1)
  end

  local vsplit_func = function()
    self:open_link(2)
  end

  local split_func = function()
    self:open_link(3)
  end

  local quit_func = function()
    self:quit_float_window()
  end

  local keymaps = {
    { 'n', move.prev, '<Up>', opts },
    { 'n', move.next, '<Down>', opts },
    { 'n', action.vsplit, vsplit_func, opts },
    { 'n', action.split, split_func, opts },
    {
      'n',
      action.scroll_down,
      function()
        self:scroll_in_preview(1)
      end,
      opts,
    },
    {
      'n',
      action.scroll_up,
      function()
        self:scroll_in_preview(-1)
      end,
      opts,
    },
  }

  if type(action.open) == 'table' then
    for _, key in ipairs(action.open) do
      insert(keymaps, { 'n', key, open_func, opts })
    end
  elseif type(action.open) == 'string' then
    insert(keymaps, { 'n', action.open, open_func, opts })
  end

  if type(action.quit) == 'table' then
    for _, key in ipairs(action.quit) do
      insert(keymaps, { 'n', key, quit_func, opts })
    end
  elseif type(action.quit) == 'string' then
    insert(keymaps, { 'n', action.quit, quit_func, opts })
  end
  nvim_create_keymap(keymaps)
end

function Finder:lsp_finder_highlight()
  local def_uri_count = self.definition_uri == 0 and -1 or self.definition_uri
  local def_len = string.len('Definition')
  local ref_len = string.len('References')
  -- add syntax
  api.nvim_buf_add_highlight(self.bufnr, -1, 'DefinitionsIcon', 0, 0, #icons.def)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'Definitions', 0, #icons.def, #icons.def + def_len)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'DefinitionCount', 0, #icons.def + def_len, -1)
  api.nvim_buf_add_highlight(self.bufnr, -1, 'ReferencesIcon', 3 + def_uri_count, 0, #icons.ref)
  api.nvim_buf_add_highlight(
    self.bufnr,
    -1,
    'References',
    3 + def_uri_count,
    #icons.ref,
    #icons.ref + ref_len
  )
  api.nvim_buf_add_highlight(
    self.bufnr,
    -1,
    'ReferencesCount',
    3 + def_uri_count,
    #icons.ref + ref_len,
    -1
  )
end

local finder_ns = api.nvim_create_namespace('finder_select')

function Finder:set_cursor()
  local current_line = api.nvim_win_get_cursor(0)[1]
  local column = #indent + #self.f_icon + 1

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

  local actual_line = api.nvim_win_get_cursor(0)[1]
  if actual_line == first_def_uri_lnum then
    api.nvim_buf_add_highlight(
      0,
      finder_ns,
      'LspSagaFinderSelection',
      2,
      #indent + #self.f_icon,
      -1
    )
  end

  api.nvim_buf_clear_namespace(0, finder_ns, 0, -1)
  api.nvim_buf_add_highlight(
    0,
    finder_ns,
    'LspSagaFinderSelection',
    actual_line - 1,
    #indent + #self.f_icon,
    -1
  )
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
  local current_line = api.nvim_win_get_cursor(0)[1]

  if self.short_link[current_line] == nil then
    error('[LspSaga] target file uri not exist')
    return
  end

  self:quit_float_window(false)
  if vim.bo.modified then
    vim.cmd('write')
  end
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
  current_win_lnum =
    scroll_in_win(pdata[1], direction, current_win_lnum, last_lnum, config.max_preview_lines)
  api.nvim_win_set_var(0, 'saga_finder_preview', { pdata[1], current_win_lnum, last_lnum })
end

function Finder:quit_float_window(...)
  self:close_auto_preview_win()
  if self.winid ~= 0 then
    window.nvim_close_valid_window({ self.winid, self.titlebar_winid })
  end

  local args = { ... }
  local clear = true

  if #args > 0 then
    clear = args[1]
  end

  if clear then
    self:clear_tmp_data()
  end
end

function Finder:clear_tmp_data()
  self.short_link = {}
  self.contents = {}
  self.definition_uri = 0
  self.reference_uri = 0
  self.param_length = nil
  self.buf_filetype = ''
  self.WIN_HEIGHT = 0
  self.WIN_WIDTH = 0
end

return Finder
