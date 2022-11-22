local libs, window = require('lspsaga.libs'), require('lspsaga.window')
local config = require('lspsaga').config_values
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymap.set
local def = {}
local method = 'textDocument/definition'

--- @deprecated when 0.9 release
function def:title_text(opts, scope)
  local link = scope.link
  local path_sep = libs.path_sep
  local root_dir = libs.get_lsp_root_dir()
  if not root_dir then
    root_dir = ''
  end

  local short_name
  if link:find(root_dir, 1, true) then
    short_name = link:sub(root_dir:len() + 2)
  else
    local _split = vim.split(link, path_sep)
    if #_split >= 4 then
      short_name = table.concat(_split, path_sep, #_split - 2, #_split)
    end
  end
  opts.title = short_name
  opts.title_pos = 'center'
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
  if not libs.check_lsp_active() then
    return
  end

  local scope = {}

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

  lsp.buf_request_all(current_buf, method, params, function(results)
    if not results or next(results) == nil then
      vim.notify('[Lspsaga] response of request method ' .. method .. ' is nil')
      return
    end

    local result
    for _, res in pairs(results) do
      if res and res.result then
        result = res.result
      end
    end

    if not result then
      vim.notify('[Lspsaga] response of request method ' .. method .. ' is nil')
      return
    end

    local uri, range

    if type(result[1]) == 'table' then
      uri = result[1].uri or result[1].targetUri
      range = result[1].range or result[1].targetRange
    else
      uri = result.uri or result.targetUri
      range = result.range or result.targetRange
    end

    if not uri then
      return
    end

    local bufnr = vim.uri_to_bufnr(uri)
    scope.link = vim.uri_to_fname(uri)

    if not api.nvim_buf_is_loaded(bufnr) then
      fn.bufload(bufnr)
    end

    local start_line = range.start.line
    local start_char_pos = range.start.character
    local end_char_pos = range['end'].character

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
      highlight = 'DefinitionBorder',
    }

    if fn.has('nvim-0.9') == 1 then
      self:title_text(opts, scope)
    end

    _, scope.winid = window.create_win_with_border(content_opts, opts)
    vim.opt_local.modifiable = true
    api.nvim_win_set_buf(scope.winid, bufnr)
    scope.bufnr = bufnr
    api.nvim_buf_set_option(scope.bufnr, 'bufhidden', 'wipe')

    if fn.has('nvim-0.8') == 1 then
      api.nvim_win_set_option(scope.winid, 'winbar', '')
    end
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

function def:apply_aciton_keys(bufnr, pos)
  local maps = config.definition_action_keys
  for action, key in pairs(maps) do
    if action ~= 'close' then
      keymap('n', key, function()
        local scope = self:find_current_scope()
        local link, def_win_ns = scope.link, scope.def_win_ns

        api.nvim_buf_clear_namespace(bufnr, def_win_ns, 0, -1)

        self:close_window(scope)
        if action ~= 'quit' then
          vim.cmd(action .. ' ' .. link)
          api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
        end
        self:remove_scope(scope)
      end, { buffer = bufnr })
    end
  end

  keymap('n', maps.close, function()
    local scope = self:find_current_scope()
    local main_winid = self[scope.main_bufnr].main_winid
    for _, v in pairs(self[scope.main_bufnr].scopes) do
      self:close_window(v)
    end
    api.nvim_set_current_win(main_winid)
    self[scope.main_bufnr] = nil
  end, { buffer = bufnr })
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

return def
