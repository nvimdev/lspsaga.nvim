local libs, window = require('lspsaga.libs'), require('lspsaga.window')
local config = require('lspsaga').config_values
local lsp, fn, api = vim.lsp, vim.fn, vim.api
local scroll_in_win = require('lspsaga.action').scroll_in_win
local def = {}
local saga_augroup = require('lspsaga').saga_augroup
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

    local result = {}
    for _, res in pairs(results) do
      if res and next(res) ~= nil then
        result = res.result
      end
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
    local start_line = 0
    if range.start.line - 3 >= 1 then
      start_line = range.start.line - 3
    else
      start_line = range.start.line
    end

    local content = vim.api.nvim_buf_get_lines(
      bufnr,
      start_line,
      range['end'].line + 1 + config.max_preview_lines,
      false
    )
    content = vim.list_extend(
      { config.definition_preview_icon .. 'Definition Preview: ' .. short_name, '' },
      content
    )

    local opts = {
      relative = 'cursor',
      style = 'minimal',
    }
    local WIN_WIDTH = api.nvim_get_option('columns')
    local max_width = math.floor(WIN_WIDTH * 0.5)
    local width, _ = vim.lsp.util._make_floating_popup_size(content, opts)

    if width > max_width then
      opts.width = max_width
    end

    local content_opts = {
      contents = content,
      filetype = filetype,
      highlight = 'LspSagaDefPreviewBorder',
    }

    self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)

    api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufHidden', 'BufLeave' }, {
      buffer = current_buf,
      once = true,
      callback = function()
        if self.winid ~= nil then
          window.nvim_close_valid_window(self.winid)
        end
        self:clear_tmp_data()
      end,
    })
    vim.api.nvim_buf_add_highlight(self.bufnr, -1, 'DefinitionPreviewTitle', 0, 0, -1)
    libs.scroll_in_preview(current_buf, self.winid)
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
