local api, fn, lsp = vim.api, vim.fn, vim.lsp
local config = require('lspsaga').config
local win = require('lspsaga.window')
local util = require('lspsaga.util')
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

    local cmd
    if util.iswin then
      cmd = '!start cmd /cstart /b '
    elseif util.ismac then
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
  local content = vim.split(res.value, '\n', { trimempty = true })
  local new = {}
  local in_codeblock = false
  for _, line in ipairs(content) do
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

  local max_float_width = math.floor(vim.o.columns * config.hover.max_width)
  local max_content_len = util.get_max_content_length(content)
  local increase = util.win_height_increase(content)
  local max_height = math.floor(vim.o.lines * config.hover.max_height)

  local float_option = {
    width = math.min(max_content_len, max_float_width),
    height = math.min(#content + increase, max_height),
    zindex = 80,
  }

  if option_fn then
    float_option = vim.tbl_extend('keep', float_option, option_fn(float_option.width))
  end

  if config.ui.title then
    float_option.title = {
      { config.ui.hover, 'Exception' },
      { ' Hover', 'TitleString' },
    }
  end

  local curbuf = api.nvim_get_current_buf()

  self.bufnr, self.winid = win
    :new_float(float_option)
    :setlines(content)
    :bufopt({
      ['filetype'] = (res.kind or 'markdown'),
      ['modifiable'] = false,
    })
    :winopt({
      ['winhl'] = 'NormalFloat:HoverNormal,Border:HoverBorder',
      ['conceallevel'] = 2,
      ['concealcursor'] = 'niv',
      ['showbreak'] = 'NONE',
    })
    :wininfo()

  api.nvim_buf_set_name(self.bufnr, 'lspaga_hover')

  vim.treesitter.start(self.bufnr, 'markdown')
  vim.treesitter.query.set(
    'markdown',
    'highlights',
    [[
      ([
        (info_string)
        (fenced_code_block_delimiter)
      ] @conceal
      (#set! conceal ""))
    ]]
  )

  util.scroll_in_float(curbuf, self.winid)

  util.map_keys(self.bufnr, 'n', 'q', function()
    if self.winid and api.nvim_win_is_valid(self.winid) then
      api.nvim_win_close(self.winid, true)
      self:remove_data()
    end
  end)

  if not option_fn then
    api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufDelete', 'WinScrolled' }, {
      buffer = curbuf,
      callback = function(opt)
        if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) then
          util.delete_scroll_map(curbuf)
          api.nvim_buf_delete(self.bufnr, { force = true })
        end

        if self.winid and api.nvim_win_is_valid(self.winid) then
          api.nvim_win_close(self.winid, true)
          self:remove_data()
        end

        if opt.event == 'WinScrolled' then
          vim.cmd('Lspsaga hover_doc')
        end
        api.nvim_del_autocmd(opt.id)
      end,
      desc = '[Lspsaga] Auto close hover window',
    })

    api.nvim_create_autocmd('BufEnter', {
      callback = function(opt)
        if opt.buf ~= self.bufnr and self.winid and api.nvim_win_is_valid(self.winid) then
          api.nvim_win_close(self.winid, true)
          pcall(api.nvim_del_autocmd, opt.id)
          self:remove_data()
        end
      end,
    })
  end

  util.map_keys(self.bufnr, 'n', config.hover.open_link, function()
    open_link()
  end)
end

local function ignore_error(args)
  if args and has_arg(args, '++silent') then
    return true
  end
end

function hover:do_request(args)
  local params = lsp.util.make_position_params()
  local method = 'textDocument/hover'
  local client = util.get_client_by_method(method)
  if not client then
    self.pending_request = false
    vim.notify('[Lspsaga] all server of buffer not support hover request')
    return
  end

  client.request(method, params, function(_, result, ctx)
    self.pending_request = false

    if api.nvim_get_current_buf() ~= ctx.bufnr then
      return
    end

    if not result or not result.contents then
      if ignore_error(args) then
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
      if vim.tbl_isempty(result.contents) and ignore_error(args) then
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
      if ignore_error(args) then
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
  end, api.nvim_get_current_buf())
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
  for _, p in ipairs(parsers) do
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

  if self.pending_request then
    print('[Lspsaga] There is already a hover request, please wait for the response.')
    return
  end

  if self.winid and api.nvim_win_is_valid(self.winid) then
    if (args and not has_arg(args, '++keep')) or not args then
      api.nvim_set_current_win(self.winid)
      return
    elseif args and has_arg(args, '++keep') then
      util.delete_scroll_map(api.nvim_get_current_buf())
      api.nvim_win_close(self.winid, true)
      self:remove_data()
      return
    end
  end

  self.pending_request = true
  self:do_request(args)
end

return hover
