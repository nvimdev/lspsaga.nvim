local api, lsp, util = vim.api, vim.lsp, vim.lsp.util
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local hover = {}

function hover:open_floating_preview(res, opts)
  vim.validate({
    res = { res, 't' },
    opts = { opts, 't', true },
  })
  opts = opts or {}
  opts.stylize_markdown = opts.stylize_markdown ~= false and vim.g.syntax_on ~= nil
  opts.focus = opts.focus ~= false

  local bufnr = api.nvim_get_current_buf()
  self.preview_bufnr = api.nvim_create_buf(false, true)

  local content = vim.split(res.value, '\n', { trimempty = true })
  content = vim.tbl_filter(function(s)
    return #s > 0
  end, content)

  local max_float_width = window.get_max_float_width()
  local max_content_len = window.get_max_content_length(content)
  local increase = 0
  if max_content_len > max_float_width then
    vim.tbl_map(function(s)
      if s:find('http') then
        return
      end

      if #s > max_float_width then
        increase = increase + math.ceil(#s / max_float_width)
      end
    end, content)
  end

  local theme = require('lspsaga').theme()
  local float_option = {
    width = max_float_width,
    height = #content + increase,
    no_size_override = true,
    title = {
      { theme.left, 'HoverSymbol' },
      { 'Hover', 'HoverTitle' },
      { theme.right, 'HoverSymbol' },
    },
  }

  local contents_opt = {
    contents = content,
    filetype = res.kind or 'markdown',
    wrap = true,
    highlight = {
      normal = 'HoverNormal',
      border = 'HoverBorder',
    },
    bufnr = self.preview_bufnr,
  }
  _, self.preview_winid = window.create_win_with_border(contents_opt, float_option)

  vim.wo[self.preview_winid].conceallevel = 2
  vim.wo[self.preview_winid].concealcursor = 'niv'
  vim.wo[self.preview_winid].showbreak = 'NONE'
  vim.wo[self.preview_winid].fillchars = 'lastline: '
  vim.treesitter.start(self.preview_bufnr, 'markdown')

  vim.keymap.set('n', 'q', function()
    if self.preview_bufnr and api.nvim_buf_is_loaded(self.preview_bufnr) then
      api.nvim_buf_delete(self.preview_bufnr, { force = true })
    end
  end, { buffer = self.preview_bufnr })

  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      if api.nvim_buf_is_loaded(self.preview_bufnr) then
        pcall(libs.delete_scroll_map, bufnr)
      end

      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
        self.preview_winid = nil
      end
    end,
    desc = '[Lspsaga] Auto close hover window',
  })

  libs.scroll_in_preview(bufnr, self.preview_winid)
end

function hover:handler(result)
  if not result.contents then
    vim.notify('No information available')
    return
  end
  self:open_floating_preview(result.contents)
end

function hover:do_request()
  local params = util.make_position_params()
  lsp.buf_request_all(0, 'textDocument/hover', params, function(results)
    local result = {}
    for _, res in pairs(results) do
      if res and res.result and res.result.contents then
        result = res.result
      end
    end
    self:handler(result)
  end)
end

function hover:render_hover_doc()
  if vim.fn.has('nvim-0.9') == 0 then
    vim.notify('[Lspsaga] Hover now only support for neovim 0.9+ Please use neovim 0.9')
    return
  end
  if hover.preview_winid and api.nvim_win_is_valid(hover.preview_winid) then
    api.nvim_set_current_win(hover.preview_winid)
    return
  end

  if vim.bo.filetype == 'help' then
    api.nvim_feedkeys('K', 'ni', true)
    return
  end

  self:do_request()
end

return hover
