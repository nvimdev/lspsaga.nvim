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

local function open_link()
  local ts_utils = require('nvim-treesitter.ts_utils')
  local node = ts_utils.get_node_at_cursor()

  if node ~= nil and node:type() ~= 'inline_link' then
    node = node:parent()
  end

  if node ~= nil and node:type() == 'inline_link' then
    local path

    for i = 0, node:named_child_count() - 1, 1 do
      local child = node:named_child(i)
      if child:type() == 'link_destination' then
        ---@diagnostic disable-next-line: undefined-field
        path = vim.treesitter.get_node_text(child, 0)
        break
      end
    end

    if path:find('#') then
      vim.fn.escape(path, '#')
    end

    local cmd
    if libs.iswin then
      cmd = '!start cmd /cstart /b '
    elseif libs.ismac then
      cmd = 'silent !open '
    else
      cmd = config.hover.open_browser .. ' '
    end

    if path and path:find('file://') then
      vim.cmd.edit(vim.uri_to_fname(path))
    else
      fn.execute(cmd .. '"' .. fn.escape(path, '#') .. '"')
    end
  end
end

function hover:open_floating_preview(res, option_fn)
  vim.validate({
    res = { res, 't' },
  })

  local bufnr = api.nvim_get_current_buf()
  self.preview_bufnr = api.nvim_create_buf(false, true)

  local content = vim.split(res.value, '\n', { trimempty = true })
  local new = {}
  local in_codeblock = false
  for _, line in pairs(content) do
    if line:find('\\') then
      line = line:gsub('\\(?![tn])', '')
    end
    if line:find('%[%w+%][^%(]') and not in_codeblock then
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
      in_codeblock = true
    end
    if line:find('</pre>') then
      line = line:gsub('</pre>', '```')
      in_codeblock = false
    end
    if line:find('```') then
      in_codeblock = in_codeblock and false or true
    end
    if #line > 0 then
      new[#new + 1] = line
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
  vim.bo[self.preview_bufnr].modifiable = false

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
        api.nvim_del_autocmd(opt.id)
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

  api.nvim_buf_set_keymap(self.preview_bufnr, 'n', config.hover.open_link, '', {
    nowait = true,
    noremap = true,
    callback = function()
      open_link()
    end,
  })

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    libs.scroll_in_preview(bufnr, self.preview_winid)
  end
end

local function should_error(args)
  -- Never error if we have ++quiet
  if args and has_arg(args, '++quiet') then
    return false
  end
  return true
end

local function support_clients()
  local count = 0
  local clients = lsp.get_active_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.supports_method('textDocument/hover') then
      count = count + 1
      break
    end
  end
  return count, #clients
end

function hover:do_request(args)
  local params = util.make_position_params()
  local count, total = support_clients()
  if count == 0 and should_error(args) then
    self.pending_request = false
    vim.notify('[Lspsaga] all server of buffer not support hover request')
    return
  end
  count = 0

  local failed = 0
  lsp.buf_request(0, 'textDocument/hover', params, function(_, result, ctx)
    self.pending_request = false
    count = count + 1

    if api.nvim_get_current_buf() ~= ctx.bufnr then
      return
    end

    if not result or not result.contents then
      failed = failed + 1
      if count == total and failed == total and should_error(args) then
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
      if vim.tbl_isempty(result.contents) and should_error(args) then
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

    if not value or #value == 0 then
      if should_error(args) then
        vim.notify('No information available')
      end
      return
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
      '[Lspsaga.nvim] Please install markdown and markdown_inline parser in nvim-treesitter',
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
      api.nvim_win_close(self.preview_winid, true)
      self.preview_winid = nil
      self.preview_bufnr = nil
      return
    end
  end

  if vim.bo.filetype == 'help' then
    api.nvim_feedkeys('K', 'ni', true)
    return
  end

  if self.pending_request then
    print('[Lspsaga] There is already a hover request, please wait for the response.')
    return
  end

  self.pending_request = true
  self:do_request(args)
end

function hover:has_hover()
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    return true
  end
  return false
end

return hover
