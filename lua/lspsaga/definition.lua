local libs, window = require('lspsaga.libs'), require('lspsaga.window')
local config = require('lspsaga').config_values
local lsp, fn, api = vim.lsp, vim.fn, vim.api
local def = {}
local method = 'textDocument/definition'

function def:render_title_win(opts, link)
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
  self.title_bufnr, self.title_winid = window.create_win_with_border(content_opts, opts)
  local ns_id = api.nvim_create_namespace('LspsagaDefinition')
  api.nvim_buf_set_extmark(self.title_bufnr, ns_id, 0, 0, {
    virt_text = { { '┃', 'DefinitionArrow' }, { ' ', 'DefinitionArrow' } },
    virt_text_pos = 'overlay',
  })
  api.nvim_buf_set_extmark(self.title_bufnr, ns_id, 0, 0, {
    virt_text = { { ' ', 'DefinitionArrow' }, { '┃', 'DefinitionArrow' } },
    virt_text_pos = 'eol',
  })

  api.nvim_buf_add_highlight(self.title_bufnr, 0, 'DefinitionFile', 0, 0, -1)
end

function def:peek_definition()
  if not libs.check_lsp_active() then
    return
  end

  local filetype = vim.api.nvim_buf_get_option(0, 'filetype')
  local params = lsp.util.make_position_params()

  local current_buf = api.nvim_get_current_buf()
  lsp.buf_request_all(current_buf, method, params, function(results)
    if not results or next(results) == nil then
      vim.notify('[Lspsaga] response of request method ' .. method .. ' is nil')
      return
    end

    local result
    for _, res in pairs(results) do
      if res and next(res) ~= nil then
        result = res.result
      end
    end

    if not result then
      vim.notify('[Lspsaga] response of request method ' .. method .. ' is nil')
      return
    end

    local uri = result[1].uri or result[1].targetUri
    if #uri == 0 then
      return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri)

    if not vim.api.nvim_buf_is_loaded(bufnr) then
      fn.bufload(bufnr)
    end

    local range = result[1].targetRange or result[1].range
    local start_line = range.start.line
    local start_char_pos = range.start.character
    local end_char_pos = range['end'].character

    local opts = {
      relative = 'cursor',
      style = 'minimal',
    }
    local WIN_WIDTH = api.nvim_get_option('columns')
    local max_width = math.floor(WIN_WIDTH * 0.6)
    local max_height = math.floor(vim.o.lines * 0.4)

    opts.width = max_width
    opts.height = max_height

    opts = lsp.util.make_floating_popup_options(max_width, max_height, opts)

    self:render_title_win(opts, link)

    opts.row = opts.row + 1
    local content_opts = {
      contents = {},
      filetype = filetype,
      enter = true,
      highlight = 'DefinitionBorder',
    }

    self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
    vim.opt_local.modifiable = true
    api.nvim_win_set_buf(0, bufnr)
    if vim.fn.has('nvim-0.8') == 1 then
      api.nvim_win_set_option(self.winid, 'winbar', '')
    end
    --set the initail cursor pos
    api.nvim_win_set_cursor(self.winid, { start_line + 1, start_char_pos })
    vim.cmd('normal! zt')

    local def_win_ns = api.nvim_create_namespace('DefinitionWinNs')
    api.nvim_buf_add_highlight(
      bufnr,
      def_win_ns,
      'DefinitionSearch',
      start_line,
      start_char_pos,
      end_char_pos
    )

    local quit = config.definition_action_keys.quit
    vim.keymap.set('n', quit, function()
      api.nvim_buf_clear_namespace(bufnr, def_win_ns, 0, -1)
      if self.winid and api.nvim_win_is_valid(self.winid) then
        api.nvim_win_close(self.winid, true)
        api.nvim_win_close(self.title_winid, true)
        vim.keymap.del('n', quit, { buffer = bufnr })
      end
    end, { buffer = bufnr })
      
    local enter = config.definition_action_keys.enter
    vim.keymap.set('n', enter, function()
      api.nvim_buf_clear_namespace(bufnr, def_win_ns, 0, -1)
      if self.winid and api.nvim_win_is_valid(self.winid) then
        api.nvim_win_close(self.winid, true)
        api.nvim_win_close(self.title_winid, true)
        vim.keymap.del('n', quit, { buffer = bufnr })
        vim.lsp.buf.definition()
      end
    end, { buffer = bufnr })


    api.nvim_create_autocmd('QuitPre', {
      once = true,
      callback = function()
        if self.title_winid and api.nvim_win_is_valid(self.title_winid) then
          api.nvim_win_close(self.title_winid, true)
        end
      end,
    })
  end)
end

function def:clear_tmp_data()
  for i, data in pairs(self) do
    if type(data) ~= 'function' then
      self[i] = nil
    end
  end
end

return def
