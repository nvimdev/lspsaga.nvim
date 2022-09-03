local libs, window = require('lspsaga.libs'), require('lspsaga.window')
local config = require('lspsaga').config_values
local lsp, fn, api = vim.lsp, vim.fn, vim.api
local def = {}
local path_sep = libs.path_sep
local method = 'textDocument/definition'

function def:preview_definition()
  if not libs.check_lsp_active() then
    return
  end

  local filetype = vim.api.nvim_buf_get_option(0, 'filetype')
  local params = lsp.util.make_position_params()

  local current_buf = api.nvim_get_current_buf()
  lsp.buf_request_all(current_buf, method, params, function(results)
    if not results or next(results) == nil then
      vim.notify('[Lspsaga] response of request method ' .. method .. ' is nil from ')
      return
    end

    local result
    for _, res in pairs(results) do
      if res and next(res) ~= nil then
        result = res.result
      end
    end

    if not result then
      vim.notify('[Lspsaga] response of request method ' .. method .. ' is nil from ')
      return
    end

    local uri = result[1].uri or result[1].targetUri
    if #uri == 0 then
      return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri)
    local short_name
    local root_dir = libs.get_lsp_root_dir()
    if not root_dir then
      root_dir = ''
    end

    -- reduce filename length by root_dir or home dir
    if link:find(root_dir, 1, true) then
      short_name = link:sub(root_dir:len() + 2)
    else
      local _split = vim.split(link, path_sep)
      if #_split >= 4 then
        short_name = table.concat(_split, path_sep, #_split - 2, #_split)
      end
    end

    if not vim.api.nvim_buf_is_loaded(bufnr) then
      fn.bufload(bufnr)
    end

    local range = result[1].targetRange or result[1].range
    local start_line = range.start.line
    local start_char_pos = range.start.character

    local prompt = config.definition_preview_icon .. 'File: '
    local quit = config.definition_action_keys.quit

    local opts = {
      relative = 'cursor',
      style = 'minimal',
    }
    local WIN_WIDTH = api.nvim_get_option('columns')
    local max_width = math.floor(WIN_WIDTH * 0.6)
    local max_height = math.floor(vim.o.lines * 0.6)

    opts.width = max_width
    opts.height = max_height

    local content_opts = {
      contents = {},
      filetype = filetype,
      enter = true,
      highlight = 'DefinitionBorder',
    }

    self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
    vim.opt_local.modifiable = true
    api.nvim_win_set_buf(0, bufnr)
    api.nvim_win_set_option(self.winid, 'winbar', '')
    --set the initail cursor pos
    api.nvim_win_set_cursor(self.winid, { start_line + 1, start_char_pos })

    vim.keymap.set('n', quit, function()
      if self.winid and api.nvim_win_is_valid(self.winid) then
        api.nvim_win_close(self.winid, true)
        vim.keymap.del('n', quit, { buffer = bufnr })
      end
    end, { buffer = bufnr })
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
