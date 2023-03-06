local api, fn, lsp, util = vim.api, vim.fn, vim.lsp, vim.lsp.util
local config = require('lspsaga').config
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local hover = {}

local function has_arg(args, arg)
  local tbl = vim.split(args, '%s')
  if vim.tbl_contains(tbl, arg) then
    return true
  end
  return false
end

function hover:open_floating_preview(res, option_fn)
  vim.validate({
    res = { res, 't' },
  })

  local bufnr = api.nvim_get_current_buf()
  local cur_winline = vim.fn.winline() - 1
  self.preview_bufnr = api.nvim_create_buf(false, true)

  local content = vim.split(res.value, '\n', { trimempty = true })
  if #content == 0 then
    vim.notify('No information available')
    return
  end

  local new = {}
  for i, line in pairs(content) do
    if line:find('\\') then
      line = line:gsub('\\', '')
    end
    if line:find('%[%w+%][^%(]') and not content[i - 1]:find('```') then
      line = line:gsub('%[', '%[%[')
      line = line:gsub('%]', '%]%]')
    end
    if line:find('\r') then
      line = line:gsub('\r\n?', ' ')
    end
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

  local max_float_width = math.floor(vim.o.columns * config.hover.max_width)
  local max_content_len = window.get_max_content_length(content)
  local increase = window.win_height_increase(content)
  local max_height = math.floor(vim.o.lines * 0.8)

  local float_option = {
    width = max_content_len < max_float_width and max_content_len or max_float_width,
    height = #content + increase > max_height and max_height or #content + increase,
    no_size_override = true,
    zindex = 80,
  }

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    float_option.title = {
      { config.ui.hover, 'Exception' },
      { ' Hover', 'TitleString' },
    }
  end

  if option_fn then
    local new_opt = option_fn(float_option.width)
    float_option = vim.tbl_extend('keep', float_option, new_opt)
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
    api.nvim_set_option_value(
      'fillchars',
      'lastline: ',
      { scope = 'local', win = self.preview_winid }
    )
    vim.treesitter.start(self.preview_bufnr, 'markdown')
  end

  vim.keymap.set('n', 'q', function()
    if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
      api.nvim_win_close(self.preview_winid, true)
      self:remove_data()
    end
  end, { buffer = self.preview_bufnr })

  if not option_fn then
    api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufDelete', 'WinScrolled' }, {
      buffer = bufnr,
      once = true,
      callback = function(opt)
        if self.preview_bufnr and api.nvim_buf_is_loaded(self.preview_bufnr) then
          libs.delete_scroll_map(bufnr)
          api.nvim_buf_delete(self.preview_bufnr, { force = true })
        end

        if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
          api.nvim_win_close(self.preview_winid, true)
          self:remove_data()
        end

        if opt.event == 'WinScrolled' then
          vim.cmd('Lspsaga hover_doc')
        end
      end,
      desc = '[Lspsaga] Auto close hover window',
    })

    self.enter_leave_id = api.nvim_create_autocmd('BufEnter', {
      callback = function(opt)
        if
          opt.buf ~= self.preview_bufnr
          and self.preview_winid
          and api.nvim_win_is_valid(self.preview_winid)
        then
          api.nvim_win_close(self.preview_winid, true)
          if self.enter_leave_id then
            pcall(api.nvim_del_autocmd, self.enter_leave_id)
          end
          self:remove_data()
        end
      end,
    })
  end
  libs.scroll_in_preview(bufnr, self.preview_winid)
end

function hover:do_request(args)
  local params = util.make_position_params()
  lsp.buf_request(0, 'textDocument/hover', params, function(_, result, ctx)
    if api.nvim_get_current_buf() ~= ctx.bufnr then
      return
    end

    if not result or not result.contents then
      if not args or not has_arg(args, '++quiet') then
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
      if vim.tbl_isempty(result.contents) then
        vim.notify('No information available')
        return
      end
      local values = {}
      for _, ms in ipairs(result.contents) do
        ---@diagnostic disable-next-line: undefined-field
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

    local option_fn
    if args and has_arg(args, '++keep') then
      option_fn = function(width)
        local opt = {}
        opt.relative = 'editor'
        opt.row = 1
        opt.col = vim.o.columns - width - 3
        return opt
      end
    end

    self:open_floating_preview(result.contents, option_fn)
  end)
end

function hover:remove_data()
  for k, v in pairs(self) do
    if type(v) ~= 'function' then
      self[k] = nil
    end
  end
end

local function check_parser()
  local parsers = { 'parser/markdown.so', 'parser/markdown_inline.so' }
  local has_parser = true
  for _, p in pairs(parsers) do
    if #api.nvim_get_runtime_file(p, true) == 0 then
      has_parser = false
      break
    end
  end
  return has_parser
end

function hover:render_hover_doc(args)
  if not check_parser() then
    vim.notify(
      '[Lpsaga.nvim] Please install markdown and markdown_inline parser in nvim-treesitter',
      vim.log.levels.WARN
    )
    return
  end

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    if (args and not has_arg(args, '++keep')) or not args then
      api.nvim_set_current_win(self.preview_winid)
      return
    elseif args and has_arg(args, '++keep') then
      libs.delete_scroll_map(api.nvim_get_current_buf())
      window.nvim_close_valid_window(self.preview_winid)
      self.preview_winid = nil
      self.preview_bufnr = nil
      return
    end
  end

  if vim.bo.filetype == 'help' then
    api.nvim_feedkeys('K', 'ni', true)
    return
  end

  self:do_request(args)
end

function hover:has_hover()
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    return true
  end
  return false
end

return hover
