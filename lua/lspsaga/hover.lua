local api, fn, lsp, util = vim.api, vim.fn, vim.lsp, vim.lsp.util
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

  local new = {}
  for _, line in pairs(content) do
    if line:find('&nbsp;') then
      line = line:gsub('&nbsp;', ' ')
    end
    if line:find('&lt;') then
      line = line:gsub('&lt;', '<')
    end
    if line:find('&gt;') then
      line = line:gsub('&gt;', '>')
    end
    if line:find('<pre>') then
      line = line:gsub('<pre>', '```')
    end
    if line:find('</pre>') then
      line = line:gsub('</pre>', '```')
    end
    if #line > 0 then
      table.insert(new, line)
    end
  end
  content = new

  local window = require('lspsaga.window')
  local libs = require('lspsaga.libs')
  local max_float_width = math.floor(vim.o.columns * 0.6)
  local max_content_len = window.get_max_content_length(content)
  local increase = window.win_height_increase(content)

  local theme = require('lspsaga').theme()
  local float_option = {
    width = max_content_len > max_float_width and max_float_width or max_content_len,
    height = #content + increase,
    no_size_override = true,
  }

  if fn.has('nvim-0.9') == 1 then
    float_option.title = {
      { theme.left, 'TitleSymbol' },
      { 'Hover', 'TitleString' },
      { theme.right, 'TitleSymbol' },
    }
  end

  local contents_opt = {
    contents = content,
    filetype = res.kind or 'markdown',
    buftype = 'nofile',
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
  if fn.has('nvim-0.9') == 1 then
    vim.wo[self.preview_winid].fcs = 'lastline: '
    vim.treesitter.start(self.preview_bufnr, 'markdown')
  end

  vim.keymap.set('n', 'q', function()
    if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
      api.nvim_win_close(self.preview_winid, true)
      self:remove_data()
    end
  end, { buffer = self.preview_bufnr })

  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      if self.preview_bufnr and api.nvim_buf_is_loaded(self.preview_bufnr) then
        libs.delete_scroll_map(bufnr)
        api.nvim_buf_delete(self.preview_bufnr, { force = true })
      end

      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
        self:remove_data()
      end
    end,
    desc = '[Lspsaga] Auto close hover window',
  })

  libs.scroll_in_preview(bufnr, self.preview_winid)
end

function hover:do_request(arg)
  local params = util.make_position_params()
  lsp.buf_request(0, 'textDocument/hover', params, function(_, result, ctx)
    if api.nvim_get_current_buf() ~= ctx.bufnr then
      return
    end

    if not result or not result.contents or next(result.contents) == nil then
      if not arg or arg ~= '++quiet' then
        vim.notify('No information available')
      end
      return
    end

    -- MarkedString | MarkedString[] | MarkupContent;
    -- type MarkedString = string | { language: string; value: string };
    -- interface MarkupContent { kind: MarkupKind; value: string; }
    local value
    if type(result.contents) == 'string' then -- MarkedString
      value = result.contents
    elseif result.contents.language then -- MarkedString
      value = result.contents.value
    elseif vim.tbl_islist(result.contents) then -- MarkedString[]
      local values = {}
      for _, ms in ipairs(result.contents) do
        table.insert(values, type(ms) == 'string' and ms or ms.value)
      end
      value = table.concat(values, '\n')
    elseif result.contents.kind then -- MarkupContent
      value = result.contents.value
    end

    result.contents = {
      kind = 'markdown',
      value = value,
    }
    self:open_floating_preview(result.contents)
  end)
end

function hover:remove_data()
  for k, v in pairs(self) do
    if type(v) ~= 'function' then
      self[k] = nil
    end
  end
end

function hover:render_hover_doc(arg)
  local has_parser = api.nvim_get_runtime_file('parser/markdown.so', true)
  if #has_parser == 0 then
    vim.notify(
      '[Lpsaga.nvim] Please install markdown parser in nvim-treesitter',
      vim.log.levels.WARN
    )
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

  self:do_request(arg)
end

return hover
