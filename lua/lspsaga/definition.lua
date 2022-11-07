local libs, window = require('lspsaga.libs'), require('lspsaga.window')
local config = require('lspsaga').config_values
local lsp, fn, api = vim.lsp, vim.fn, vim.api
local def = {}
local method = 'textDocument/definition'
local definition_group = api.nvim_create_augroup('DefinitionAutoCmdGroup', { clear = true })

function def:render_title_win(opts, scope)
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

  local content_opts = {
    contents = { '   Definition: ' .. short_name .. ' ' },
    border = 'none',
  }
  scope.title_bufnr, scope.title_winid = window.create_win_with_border(content_opts, opts)
  local ns_id = api.nvim_create_namespace('LspsagaDefinition')
  api.nvim_buf_set_extmark(scope.title_bufnr, ns_id, 0, 0, {
    virt_text = { { '┃', 'DefinitionArrow' }, { ' ', 'DefinitionArrow' } },
    virt_text_pos = 'overlay',
  })
  api.nvim_buf_set_extmark(scope.title_bufnr, ns_id, 0, 0, {
    virt_text = { { ' ', 'DefinitionArrow' }, { '┃', 'DefinitionArrow' } },
    virt_text_pos = 'eol',
  })

  api.nvim_buf_add_highlight(scope.title_bufnr, 0, 'DefinitionFile', 0, 0, -1)
end

function def:peek_definition()
  local scope = {}
  if not libs.check_lsp_active() then
    return
  end

  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  local current_word = vim.fn.expand('<cword>')
  local from = { api.nvim_get_current_buf(), pos[1], pos[2] + 1, 0 }
  local items = { { tagname = current_word, from = from } }
  vim.fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

  local filetype = vim.api.nvim_buf_get_option(0, 'filetype')
  local params = lsp.util.make_position_params()

  local current_buf = api.nvim_get_current_buf()
  if not self.main_winid then
    self.main_winid = api.nvim_get_current_win()
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

    if not vim.api.nvim_buf_is_loaded(bufnr) then
      fn.bufload(bufnr)
    end

    local start_line = range.start.line
    local start_char_pos = range.start.character
    local end_char_pos = range['end'].character

    local opts = {
      relative = 'cursor',
      style = 'minimal',
    }
    local WIN_WIDTH = api.nvim_get_option('columns')
    local max_width = math.floor(WIN_WIDTH * 0.6)
    local max_height = math.floor(vim.o.lines * 0.6)

    opts.width = max_width
    opts.height = max_height

    opts = lsp.util.make_floating_popup_options(max_width, max_height, opts)

    self:render_title_win(opts, scope)

    opts.row = opts.row + 1
    local content_opts = {
      contents = {},
      filetype = filetype,
      enter = true,
      highlight = 'DefinitionBorder',
    }

    scope.bufnr, scope.winid = window.create_win_with_border(content_opts, opts)
    vim.opt_local.modifiable = true
    api.nvim_win_set_buf(0, bufnr)
    if vim.fn.has('nvim-0.8') == 1 then
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

    self:apply_aciton_keys(scope, bufnr, { start_line, start_char_pos })
    self:apply_autocmds(scope)
  end)
end

function def:apply_autocmds(scope)
  api.nvim_create_autocmd('WinClosed', {
    desc = 'Remove the title window when the related content window is closed',
    group = definition_group,
    pattern = { tostring(scope.winid) },
    callback = function()
      if scope.title_winid and api.nvim_win_is_valid(scope.title_winid) then
        api.nvim_win_close(scope.title_winid, true)
      end
    end,
  })
end

function def:apply_aciton_keys(scope, bufnr, pos)
  -- Save the current scope data
  if self[bufnr] == nil then
    self[bufnr] = {}
  end
  table.insert(self[bufnr], scope)

  local maps = config.definition_action_keys

  for action, key in pairs(maps) do
    vim.keymap.set('n', key, function()
      local curr_scope = self:find_current_scope()
      local link, def_win_ns = curr_scope.link, curr_scope.def_win_ns

      api.nvim_buf_clear_namespace(bufnr, def_win_ns, 0, -1)

      local non_quit_action = action ~= 'quit'

      if non_quit_action then
        local win
        api.nvim_win_call(self.main_winid, function()
          vim.cmd(action .. ' ' .. link)
          win = api.nvim_get_current_win()
        end)

        if win then
          api.nvim_set_current_win(win)
          api.nvim_win_set_cursor(win, { pos[1] + 1, pos[2] })
        end
      else
        self:focus_last_window() -- INFO: Only focus the last window when `quit`
      end

      self:close_window(curr_scope, { close_all = non_quit_action })

      self:clear_tmp_data(bufnr, curr_scope, { close_all = non_quit_action })
      self:clear_all_maps(bufnr)
    end, { buffer = bufnr })
  end
end

-- Function to find the scope data for the current window
-- @return table
function def:find_current_scope()
  local curr_winid = api.nvim_get_current_win()

  local curr_scope
  for _, scopes in pairs(self) do
    if type(scopes) == 'table' then
      for _, scope in ipairs(scopes) do
        if scope.winid == curr_winid then
          curr_scope = scope
          break
        end
      end
    end
  end

  return curr_scope
end

-- Function to clear all the keymappings when there's no window
-- @param bufnr - The buffer number that those keymappings set for
function def:clear_all_maps(bufnr)
  local scopes = self[bufnr]
  local maps = config.definition_action_keys

  if scopes == nil or next(scopes) == nil then
    if api.nvim_buf_is_valid(bufnr) then
      for _, key in pairs(maps) do
        vim.keymap.del('n', key, { buffer = bufnr })
      end
    end
  end
end

-- Function to close the given window
-- @param curr_scope - Scope data for the current window
-- @param opts       - Options including `close_all`
function def:close_window(curr_scope, opts)
  opts = opts or {}
  local curr_bufnr = api.nvim_get_current_buf()

  local close_scope = function(item)
    local bufnr, winid = item.bufnr, item.winid
    if bufnr and api.nvim_buf_is_loaded(bufnr) then
      api.nvim_buf_delete(bufnr, { force = true })
    end

    if winid and api.nvim_win_is_valid(winid) then
      api.nvim_win_close(winid, true)
    end
  end

  if opts.close_all then
    self:process_all_scopes(function(bufnr, scope)
      close_scope(scope)

      if bufnr ~= curr_bufnr then
        api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  elseif curr_scope ~= nil then
    close_scope(curr_scope)
  end
end

-- Function to clear the tmp data on triggering the keymap
-- @param bufnr       - Current buffer number
-- @param curr_scope  - Scope data for the current window
-- @param opts        - Options including `close_all`
function def:clear_tmp_data(bufnr, curr_scope, opts)
  opts = opts or {}

  if opts.close_all then
    self:process_all_scopes(function(key, _)
      self[key] = nil
    end)
  elseif curr_scope ~= nil then
    local scopes = self[bufnr]

    local matched_index
    if scopes ~= nil then
      for i, item in ipairs(scopes) do
        if item.winid == curr_scope.winid then
          matched_index = i
        end
      end

      if matched_index ~= nil then
        table.remove(scopes, matched_index)
      end
    end
  end

  -- INFO: unset the `main_winid` when all the definition windows are closed.
  local cleared = true
  self:process_all_scopes(function(_, _)
    cleared = false
  end)

  if cleared then
    self.main_winid = nil
  end
end

-- Function to iterate all the scopes with given callback function
-- @param cb - The callback function for each scope
function def:process_all_scopes(cb)
  for bufnr, scopes in pairs(self) do
    if type(scopes) == 'table' and api.nvim_buf_is_valid(bufnr) then
      for _, scope in ipairs(scopes) do
        cb(bufnr, scope)
      end
    end
  end
end

-- Function to find the last definition window and then focus it
function def:focus_last_window()
  local last_window
  local curr_win = api.nvim_get_current_win()
  self:process_all_scopes(function(_, scope)
    local valid_win = scope.winid ~= curr_win and api.nvim_win_is_valid(scope.winid)

    if (last_window == nil or scope.winid > last_window) and valid_win then
      last_window = scope.winid
    end
  end)

  if last_window ~= nil then
    api.nvim_set_current_win(last_window)
  end
end

return def
