local api, lsp, util = vim.api, vim.lsp, vim.lsp.util
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local wrap = require('lspsaga.wrap')
local hover = {}

function hover:open_floating_preview(contents, opts)
  vim.validate({
    contents = { contents, 't' },
    opts = { opts, 't', true },
  })
  opts = opts or {}
  opts.wrap = opts.wrap ~= false -- wrapping by default
  opts.stylize_markdown = opts.stylize_markdown ~= false and vim.g.syntax_on ~= nil
  opts.focus = opts.focus ~= false
  opts.close_events = opts.close_events or { 'CursorMoved', 'InsertEnter' }

  local bufnr = api.nvim_get_current_buf()

  local floating_bufnr = api.nvim_create_buf(false, true)

  -- Clean up input: trim empty lines from the end, pad
  contents = lsp.util._trim(contents, opts)

  -- applies the syntax and sets the lines to the buffer
  contents = lsp.util.stylize_markdown(floating_bufnr, contents, opts)

  -- Compute size of float needed to show (wrapped) lines
  if opts.wrap then
    opts.wrap_at = opts.wrap_at or api.nvim_win_get_width(0)
  else
    opts.wrap_at = nil
  end
  local width, height = lsp.util._make_floating_popup_size(contents, opts)

  local max_float_width = window.get_max_float_width()

  if width > max_float_width then
    width = max_float_width
  end

  local stripped = wrap.wrap_contents(contents, width)

  height = #stripped

  local float_option = lsp.util.make_floating_popup_options(width, height, opts)

  local contents_opt = {
    contents = stripped,
    highlight = 'LspSagaHoverBorder',
    bufnr = floating_bufnr,
  }

  self.preview_bufnr, self.preview_winid = window.create_win_with_border(contents_opt, float_option)

  api.nvim_win_set_option(self.preview_winid, 'conceallevel', 2)
  api.nvim_win_set_option(self.preview_winid, 'concealcursor', 'n')
  api.nvim_win_set_option(self.preview_winid, 'foldenable', false)
  -- soft wrapping
  api.nvim_win_set_option(self.preview_winid, 'wrap', false)

  api.nvim_buf_set_keymap(
    floating_bufnr,
    'n',
    'q',
    '<cmd>bdelete<cr>',
    { silent = true, noremap = true, nowait = true }
  )

  libs.close_preview_autocmd(bufnr, self.preview_winid, opts.close_events)
  api.nvim_create_autocmd(opts.close_events, {
    buffer = bufnr,
    once = true,
    callback = function()
      if self.preview_winid and api.nvim_win_is_valid(self.preview_bufnr) then
        api.nvim_win_close(self.preview_winid, true)
        self.preview_winid = nil
      end
    end,
  })
end

function hover:handler(result)
  if not result.contents then
    vim.notify('No information available')
    return
  end
  local markdown_lines = util.convert_input_to_markdown_lines(result.contents)
  markdown_lines = util.trim_empty_lines(markdown_lines)
  if vim.tbl_isempty(markdown_lines) then
    vim.notify('No information available')
    return
  end
  self:open_floating_preview(markdown_lines)
end

function hover.render_hover_doc()
  if hover.preview_winid and api.nvim_win_is_valid(hover.preview_winid) then
    api.nvim_set_current_win(hover.preview_winid)
    return
  end

  --see #439
  if vim.bo.filetype == 'help' then
    api.nvim_feedkeys('K', 'ni', true)
    return
  end

  local params = util.make_position_params()
  lsp.buf_request_all(0, 'textDocument/hover', params, function(results)
    local result = {}
    for _, res in pairs(results) do
      if res and res.result then
        result = res.result
      end
    end
    hover:handler(result)
  end)
end

return hover
