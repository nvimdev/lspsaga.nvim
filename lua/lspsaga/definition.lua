local libs, window = require('lspsaga.libs'), require('lspsaga.window')
local config = require('lspsaga').config
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymap.set
local def = {}

function def:title_text(opts, scope)
  local link = scope.link
  link = vim.split(link, libs.path_sep, { trimempty = true })
  if #link > 2 then
    link = table.concat(link, libs.path_sep, #link - 1, #link)
  end
  local theme = require('lspsaga').theme()
  opts.title = {
    { theme.left, 'TitleSymbol' },
    { link, 'TitleString' },
    { theme.right, 'TitleSymbol' },
  }
  local data = libs.icon_from_devicon(vim.bo.filetype, true)
  if data then
    table.insert(opts.title, 2, { data[1] .. ' ', 'TitleFileIcon' })
    api.nvim_set_hl(0, 'TitleFileIcon', {
      background = config.ui.title,
      foreground = data[2],
    })
  end
end

local function get_uri_data(result)
  local uri, range

  if type(result[1]) == 'table' then
    uri = result[1].uri or result[1].targetUri
    range = result[1].range or result[1].targetRange
  else
    uri = result.uri or result.targetUri
    range = result.range or result.targetRange
  end

  if not uri then
    vim.notify('[Lspsaga] Does not find target uri', vim.log.levels.WARN)
    return
  end

  local bufnr = vim.uri_to_bufnr(uri)
  local link = vim.uri_to_fname(uri)

  if not api.nvim_buf_is_loaded(bufnr) then
    fn.bufload(bufnr)
  end

  local start_line = range.start.line
  local start_char_pos = range.start.character
  local end_char_pos = range['end'].character

  return bufnr, link, start_line, start_char_pos, end_char_pos
end

-- { [bufnr] = {
--    main_winid = number,
--    fname = string,
--    scopes = {
--     { bufnr,def_win_ns, link, winid, main_bufnr }
--    }
--  }
-- }
function def:peek_definition()
  if self.pending_request then
    vim.notify('[Lspsaga] Already have a peek_definition request please wait', vim.log.levels.WARN)
    return
  end

  if not libs.check_lsp_active() then
    return
  end

  local scope = {}
  self.pending_request = true
  local current_buf = api.nvim_get_current_buf()

  if not self[current_buf] then
    self[current_buf] = {}
    self[current_buf].scopes = {}
  end
  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  local current_word = fn.expand('<cword>')
  local from = { current_buf, pos[1], pos[2] + 1, 0 }
  local items = { { tagname = current_word, from = from } }
  fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

  local filetype = api.nvim_buf_get_option(0, 'filetype')
  local params = lsp.util.make_position_params()

  if not self[current_buf].main_winid then
    self[current_buf].main_winid = api.nvim_get_current_win()
  end

  if not self[current_buf].fname then
    self[current_buf].fname = api.nvim_buf_get_name(current_buf)
  end

  lsp.buf_request_all(current_buf, 'textDocument/definition', params, function(results)
    self.pending_request = false
    if not results or next(results) == nil then
      vim.notify(
        '[Lspsaga] response of request method textDocument/definition is nil',
        vim.log.levels.WARN
      )
      return
    end

    local result
    for _, res in pairs(results) do
      if res and res.result then
        result = res.result
      end
    end

    if not result then
      vim.notify(
        '[Lspsaga] response of request method textDocument/definition is nil',
        vim.log.levels.WARN
      )
      return
    end

    local bufnr, link, start_line, start_char_pos, end_char_pos = get_uri_data(result)
    scope.link = link

    local opts = {
      relative = 'cursor',
      style = 'minimal',
    }
    local WIN_WIDTH = vim.o.columns
    local max_width = math.floor(WIN_WIDTH * 0.6)
    local max_height = math.floor(vim.o.lines * 0.6)

    opts.width = max_width
    opts.height = max_height

    opts = lsp.util.make_floating_popup_options(max_width, max_height, opts)

    opts.row = opts.row + 1
    local content_opts = {
      contents = {},
      filetype = filetype,
      enter = true,
      highlight = {
        border = 'DefinitionBorder',
        normal = 'DefinitionNormal',
      },
    }
    --@deprecated when 0.9 release
    if fn.has('nvim-0.9') == 1 then
      self:title_text(opts, scope)
    end

    _, scope.winid = window.create_win_with_border(content_opts, opts)
    vim.opt_local.modifiable = true
    api.nvim_win_set_buf(scope.winid, bufnr)
    scope.bufnr = bufnr
    api.nvim_buf_set_option(scope.bufnr, 'bufhidden', 'wipe')
    api.nvim_win_set_option(scope.winid, 'winbar', '')
    --set the initail cursor pos
    api.nvim_win_set_cursor(scope.winid, { start_line + 1, start_char_pos })
    vim.cmd('normal! zt')

    scope.def_win_ns = api.nvim_create_namespace('DefinitionWinNs-' .. scope.bufnr)
    api.nvim_buf_add_highlight(
      bufnr,
      scope.def_win_ns,
      'DefinitionSearch',
      start_line,
      start_char_pos,
      end_char_pos
    )

    self:apply_aciton_keys(bufnr, { start_line, start_char_pos })
    self:event(bufnr)
    scope.main_bufnr = current_buf
    table.insert(self[current_buf].scopes, scope)
  end)
end

function def:find_current_scope()
  local cur_winid = api.nvim_get_current_win()
  for _, data in pairs(self) do
    if type(data) == 'table' then
      for _, v in pairs(data.scopes) do
        if v.winid == cur_winid then
          return v
        end
      end
    end
  end
end

function def:event(bufnr)
  api.nvim_create_autocmd('QuitPre', {
    buffer = bufnr,
    once = true,
    callback = function()
      local scope = self:find_current_scope()
      pcall(api.nvim_buf_clear_namespace, bufnr, scope.def_win_ns, 0, -1)
    end,
  })
end

function def:apply_aciton_keys(bufnr, pos)
  local maps = config.definition.keys
  for action, key in pairs(maps) do
    if action ~= 'close' then
      keymap('n', key, function()
        local scope = self:find_current_scope()
        local link, def_win_ns = scope.link, scope.def_win_ns
        api.nvim_buf_clear_namespace(bufnr, def_win_ns, 0, -1)
        self:clean_buf_map(scope)
        self:close_window(scope)
        if action ~= 'quit' then
          vim.cmd(action .. ' ' .. link)
          api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
        else
          -- focus prev window
          local idx = self:get_scope_index(scope)
          if idx - 1 > 0 then
            local prev_winid = self[scope.main_bufnr].scopes[idx - 1].winid
            api.nvim_set_current_win(prev_winid)
          end
        end
        self:remove_scope(scope)
      end, { buffer = bufnr })
    end
  end

  keymap('n', maps.close, function()
    local scope = self:find_current_scope()
    if not scope then
      return
    end
    local main_winid = self[scope.main_bufnr].main_winid
    for _, v in pairs(self[scope.main_bufnr].scopes) do
      self:close_window(v)
    end
    api.nvim_set_current_win(main_winid)
    self[scope.main_bufnr] = nil
  end, { buffer = bufnr })
end

function def:clean_buf_map(scope)
  local maps = config.definition.keys
  if scope.link == self[scope.main_bufnr].fname and #self[scope.main_bufnr].scopes == 1 then
    for _, v in pairs(maps) do
      vim.keymap.del('n', v, { buffer = scope.bufnr })
    end
  end
end

function def:close_window(scope)
  if scope.winid and api.nvim_win_is_valid(scope.winid) then
    api.nvim_win_close(scope.winid, true)
  end
end

function def:get_scope_index(scope)
  if self[scope.main_bufnr] then
    for k, v in pairs(self[scope.main_bufnr].scopes) do
      if v.winid == scope.winid then
        return k
      end
    end
  end
end

function def:remove_scope(scope)
  if self[scope.main_bufnr] then
    local index = self:get_scope_index(scope)
    table.remove(self[scope.main_bufnr].scopes, index)
  end
end

-- override the default the defintion handler
function def:goto_defintion()
  vim.lsp.handlers['textDocument/definition'] = function(_, result, _, _)
    if not result or vim.tbl_isempty(result) then
      return
    end
    local _, link, start_line, start_char_pos, _ = get_uri_data(result)
    api.nvim_command('edit ' .. link)
    api.nvim_win_set_cursor(0, { start_line + 1, start_char_pos })
  end
  vim.lsp.buf.definition()
end

return def
