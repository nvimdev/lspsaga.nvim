local api, util, lsp, uv, fn = vim.api, vim.lsp.util, vim.lsp, vim.loop, vim.fn
local ns = api.nvim_create_namespace('LspsagaRename')
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local config = require('lspsaga').config
local rename = {}

function rename:clean()
  for k, v in pairs(self) do
    if type(v) ~= 'function' then
      self[k] = nil
    end
  end
end

function rename:close_rename_win()
  if api.nvim_get_mode().mode == 'i' then
    vim.cmd([[stopinsert]])
  end
  if self.winid and api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
  end
  api.nvim_win_set_cursor(0, { self.pos[1], self.pos[2] })

  api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

function rename:apply_action_keys()
  local modes = { 'i', 'n', 'v' }

  for i, mode in pairs(modes) do
    vim.keymap.set(mode, config.rename.quit, function()
      self:close_rename_win()
    end, { buffer = self.bufnr })

    if i ~= 3 then
      vim.keymap.set(mode, config.rename.exec, function()
        self:do_rename()
      end, { buffer = self.bufnr })
    end
  end
end

function rename:set_local_options()
  local opt_locals = {
    scrolloff = 0,
    sidescrolloff = 0,
    modifiable = true,
  }

  for opt, val in pairs(opt_locals) do
    vim.opt_local[opt] = val
  end
end

function rename:find_reference()
  local bufnr = api.nvim_get_current_buf()
  local params = util.make_position_params()
  params.context = { includeDeclaration = true }
  local client = libs.get_client_by_cap('referencesProvider')
  if client == nil then
    return
  end

  client.request('textDocument/references', params, function(_, result)
    if not result then
      return
    end

    for _, v in pairs(result) do
      if v.range then
        local line = v.range.start.line
        local start_char = v.range.start.character
        local end_char = v.range['end'].character
        api.nvim_buf_add_highlight(bufnr, ns, 'RenameMatch', line, start_char, end_char)
      end
    end
  end, bufnr)
end

local feedkeys = function(keys, mode)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, true, true), mode, true)
end

local function support_change()
  local ok, _ = pcall(require, 'nvim-treesitter')
  if not ok then
    return true
  end

  local bufnr = api.nvim_get_current_buf()
  local queries = require('nvim-treesitter.query')
  local ft_to_lang = require('nvim-treesitter.parsers').ft_to_lang

  local lang = ft_to_lang(vim.bo[bufnr].filetype)
  local is_installed = #api.nvim_get_runtime_file('parser/' .. lang .. '.so', false) > 0
  if not is_installed then
    return true
  end
  local query = queries.get_query(lang, 'highlights')

  local ts_utils = require('nvim-treesitter.ts_utils')
  local current_node = ts_utils.get_node_at_cursor()
  if not current_node then
    return
  end
  local start_row, _, end_row, _ = current_node:range()
  for id, _, _ in query:iter_captures(current_node, 0, start_row, end_row) do
    local name = query.captures[id]
    if name:find('builtin') or name:find('keyword') then
      return false
    end
  end
  return true
end

function rename:lsp_rename()
  if not support_change() then
    vim.notify('Current is builtin or keyword,you can not rename it', vim.log.levels.WARN)
    return
  end
  local cword = fn.expand('<cword>')
  self.pos = api.nvim_win_get_cursor(0)

  local opts = {
    height = 1,
    width = 30,
  }

  local theme = require('lspsaga').theme()
  if vim.fn.has('nvim-0.9') == 1 then
    opts.title = {
      { theme.left, 'TitleSymbol' },
      { 'Rename', 'TitleString' },
      { theme.right, 'TitleSymbol' },
    }
  end

  local content_opts = {
    contents = {},
    filetype = 'sagarename',
    enter = true,
    highlight = {
      normal = 'RenameNormal',
      border = 'RenameBorder',
    },
  }

  self:find_reference()

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
  self:set_local_options()
  api.nvim_buf_set_lines(self.bufnr, -2, -1, false, { cword })

  if config.rename.in_select then
    vim.cmd([[normal! V]])
    feedkeys('<C-g>', 'n')
  end

  local quit_id, close_unfocus
  local group = require('lspsaga').saga_augroup
  quit_id = api.nvim_create_autocmd('QuitPre', {
    group = group,
    buffer = self.bufnr,
    once = true,
    nested = true,
    callback = function()
      self:close_rename_win()
      if not quit_id then
        api.nvim_del_autocmd(quit_id)
        quit_id = nil
      end
    end,
  })

  close_unfocus = api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = self.bufnr,
    callback = function()
      api.nvim_win_close(0, true)
      if close_unfocus then
        api.nvim_del_autocmd(close_unfocus)
        close_unfocus = nil
      end
    end,
  })
  self:apply_action_keys()
end

local context = {}

local function get_lsp_result()
  -- local original = lsp.handlers['textDocument/rename']
  lsp.handlers['textDocument/rename'] = function(_, result, ctx, _)
    print(vim.inspect(result))
    if not result then
      vim.notify("Language server couldn't provide rename result", vim.log.levels.INFO)
      return
    end
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    lsp.util.apply_workspace_edit(result, client.offset_encoding)
    local change
    if result.changes then
      change = result.changes
    elseif result.documentChanges then
      for _, data in pairs(result.documentChanges) do
        if not change[data['textDocument'].uri] then
          change[data['textDocument'].uri] = {}
        end
        for _, edit in pairs(data.edits) do
          table.insert(change[data['textDocument'].uri], edit)
        end
      end
    end

    for uri, data in pairs(change) do
      local fname = vim.uri_to_fname(uri)
      if not context[fname] then
        context[fname] = {}
      end
      for _, item in pairs(data) do
        table.insert(context[fname], item)
      end
    end
  end
end

function rename:do_rename()
  local new_name = vim.trim(api.nvim_get_current_line())
  self:close_rename_win()
  local current_name = vim.fn.expand('<cword>')
  local current_buf = api.nvim_get_current_buf()
  if not (new_name and #new_name > 0) or new_name == current_name then
    return
  end
  local current_win = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_win, self.pos)
  get_lsp_result()
  lsp.buf.rename(new_name)
  local lnum, col = unpack(self.pos)
  self.pos = nil
  api.nvim_win_set_cursor(current_win, { lnum, col + 1 })
  local root_dir = lsp.get_active_clients({ bufnr = current_buf })[1].config.root_dir
  if config.rename.whole_project and fn.executable('rg') == 1 and root_dir then
    local timer = uv.new_timer()
    timer:start(
      0,
      5,
      vim.schedule_wrap(function()
        if vim.tbl_count(context) > 0 and not timer:is_closing() then
          self:whole_project(current_name, new_name, root_dir)
          timer:stop()
          timer:close()
        end
      end)
    )
  end
end

function rename:p_preview()
  if self.pp_winid and api.nvim_win_is_valid(self.pp_winid) then
    api.nvim_win_close(self.pp_winid, true)
  end
  local current_line = api.nvim_win_get_cursor(0)[1]
  local lines = {}
  for _, data in pairs(context) do
    if data[1].winline == current_line then
      for _, item in pairs(data) do
        local tbl = api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)
        vim.list_extend(lines, tbl)
      end
    end
  end

  local win_conf = api.nvim_win_get_config(self.p_winid)

  local opt = {}
  opt.relative = 'editor'
  if win_conf.anchor:find('^N') then
    if win_conf.row[false] - #lines > 0 then
      opt.row = win_conf.row[false]
      opt.anchor = win_conf.anchor:gsub('N', 'S')
    else
      opt.row = win_conf.row[false] + win_conf.height + 3
      opt.anchor = win_conf.anchor
    end
  else
    if win_conf.row[false] - win_conf.height - #lines - 4 > 0 then
      opt.row = win_conf.row[false] - win_conf.height - 4
      opt.anchor = win_conf.anchor
    else
      opt.row = win_conf.row[false]
      opt.anchor = win_conf.anchor:gsub('S', 'N')
    end
  end
  opt.col = win_conf.col[false]
  local max_width = math.floor(vim.o.columns * 0.4)
  opt.width = win_conf.width < max_width and max_width or win_conf.width
  opt.height = #lines
  opt.no_size_override = true

  self.pp_bufnr, self.pp_winid = window.create_win_with_border({
    contents = lines,
    buftype = 'nofile',
    highlight = {
      normal = 'RenameNormal',
      border = 'RenameBorder',
    },
  }, opt)
end

local confirmed = {}

function rename:popup_win(lines)
  local opt = {}
  local max_len = window.get_max_content_length(lines)
  local max_width = window.get_max_float_width()
  if max_width - max_len > 10 then
    opt.width = max_len + 5
  end

  local max_height = math.floor(vim.o.lines * 0.3)
  opt.height = max_height > #context and max_height or #context
  opt.no_size_override = true

  self.p_bufnr, self.p_winid = window.create_win_with_border({
    contents = lines,
    enter = true,
    buftype = 'nofile',
    highlight = {
      normal = 'RenameNormal',
      border = 'RenameBorder',
    },
  }, opt)

  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.p_bufnr,
    callback = function()
      vim.defer_fn(function()
        self:p_preview()
      end, 10)
    end,
  })
  vim.keymap.set('n', config.rename.mark, function()
    local line = api.nvim_win_get_cursor(0)[1]
    for i, data in pairs(confirmed) do
      for _, item in pairs(data) do
        if item.winline == line then
          table.remove(confirmed, i)
          api.nvim_buf_clear_namespace(0, ns, 0, -1)
          return
        end
      end
    end

    api.nvim_buf_add_highlight(0, ns, 'FinderSelection', line - 1, 0, -1)
    for _, data in pairs(context) do
      if data[1].winline == line then
        table.insert(confirmed, data)
      end
    end
  end, { buffer = self.p_bufnr, nowait = true })

  vim.keymap.set('n', config.rename.confirm, function()
    for _, data in pairs(confirmed) do
      for _, item in pairs(data) do
        for _, match in pairs(item.submatches) do
          api.nvim_buf_set_text(
            item.bufnr,
            item.lnum - 1,
            match.start,
            item.lnum - 1,
            match['end'],
            { item.new }
          )
          api.nvim_buf_call(item.bufnr, function()
            vim.cmd.write()
          end)
        end
      end
    end
    -- clean confirmed
    confirmed = {}
    if self.p_winid and api.nvim_win_is_valid(self.p_winid) then
      api.nvim_win_close(self.p_winid, true)
    end
    if self.pp_winid and api.nvim_win_is_valid(self.pp_winid) then
      api.nvim_win_close(self.pp_winid, true)
    end
    self:clean()
  end, { buffer = self.p_bufnr, nowait = true })
end

local function check_in(fname, lnum)
  if not context[fname] then
    return false
  end

  for _, item in pairs(context[fname]) do
    if item.range.start.line + 1 == lnum then
      return true
    end
  end
  return false
end

function rename:whole_project(cur_name, new_name, root_dir)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdin = uv.new_pipe(false)

  local function safe_close(handle)
    if not uv.is_closing(handle) then
      uv.close(handle)
    end
  end

  local res = {}
  local handle, pid

  local function parse_result()
    local function decode()
      local result = {}
      for _, v in pairs(res) do
        for _, item in pairs(v) do
          local tbl = vim.json.decode(item)
          table.insert(result, tbl)
        end
      end
      return result
    end

    local parsed = decode()
    local data = {}

    for _, v in pairs(parsed) do
      local path = vim.tbl_get(v, 'data', 'path', 'text')
      local lnum = vim.tbl_get(v, 'data', 'line_number')
      if v.type == 'match' and path and lnum and not check_in(path, lnum) then
        table.insert(data, v)
      end
    end
    -- clean
    context = {}
    local lines = {}
    for i, item in pairs(data) do
      local uri = vim.uri_from_fname(item.data.path.text)
      local root_parts = vim.split(root_dir, libs.path_sep, { trimempty = true })
      local fname_parts = vim.split(item.data.path.text, libs.path_sep, { trimempty = true })
      local short = table.concat({ unpack(fname_parts, #root_parts + 1) }, libs.path_sep)
      table.insert(lines, short)
      local bufnr = vim.uri_to_bufnr(uri)
      if not api.nvim_buf_is_loaded(bufnr) then
        -- avoid lsp attached this buffer
        vim.opt.eventignore:append({ 'BufRead', 'BufReadPost', 'BufEnter', 'FileType' })
        fn.bufload(bufnr)
        vim.opt.eventignore:remove({ 'BufRead', 'BufReadPost', 'BufEnter', 'FileType' })
        if not context[uri] then
          context[uri] = {}
        end
        table.insert(context[uri], {
          bufnr = bufnr,
          new = new_name,
          lnum = item.data.line_number,
          submatches = item.data.submatches,
          winline = i,
        })
      end
    end

    self:popup_win(lines)
  end

  handle, pid = uv.spawn('rg', {
    args = { cur_name, root_dir, '--json' },
    stdio = { stdin, stdout, stderr },
  }, function(_, _)
    print(pid .. ' exit')
    uv.read_stop(stdout)
    uv.read_stop(stderr)
    safe_close(handle)
    safe_close(stdout)
    safe_close(stderr)
    -- parse after close
    vim.schedule(parse_result)
  end)

  uv.read_start(stdout, function(err, data)
    assert(not err, err)

    if data then
      local tbl = vim.split(data, '\n', { trimempty = true })
      table.insert(res, tbl)
    end
  end)
end
return rename
