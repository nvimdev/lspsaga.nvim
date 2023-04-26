local api, util, lsp, uv, fn = vim.api, vim.lsp.util, vim.lsp, vim.loop, vim.fn
local ns = api.nvim_create_namespace('LspsagaRename')
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local config = require('lspsaga').config
local rename = {}
local context = {}

rename.__index = rename
rename.__newindex = function(t, k, v)
  rawset(t, k, v)
end

local function clean_context()
  for k, _ in pairs(context) do
    context[k] = nil
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
    if string.lower(config.rename.quit) ~= '<esc>' or mode == 'n' then
      vim.keymap.set(mode, config.rename.quit, function()
        self:close_rename_win()
      end, { buffer = self.bufnr })
    end

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

function rename:lsp_rename(arg)
  if not support_change() then
    vim.notify('Current is builtin or keyword,you can not rename it', vim.log.levels.WARN)
    return
  end
  local cword = fn.expand('<cword>')
  self.pos = api.nvim_win_get_cursor(0)
  self.arg = arg

  local opts = {
    height = 1,
    width = 30,
  }

  if vim.fn.has('nvim-0.9') == 1 and config.ui.title then
    opts.title = {
      { 'Rename', 'TitleString' },
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

function rename:get_lsp_result()
  ---@diagnostic disable-next-line: duplicate-set-field
  lsp.handlers['textDocument/rename'] = function(_, result, ctx, _)
    if not result then
      vim.notify("Language server couldn't provide rename result", vim.log.levels.INFO)
      return
    end
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    lsp.util.apply_workspace_edit(result, client.offset_encoding)

    if not self.arg or (self.arg and self.arg ~= '++project') then
      return
    end

    if fn.executable('rg') == 0 then
      return
    end

    if not self.lspres then
      self.lspres = {}
    end

    if result.changes then
      for uri, change in pairs(result.changes) do
        local fname = vim.uri_to_fname(uri)
        if not self.lspres[fname] then
          self.lspres[fname] = {}
        end
        for _, edit in pairs(change) do
          self.lspres[fname][#self.lspres[fname] + 1] = edit.range
        end
      end
    elseif result.documentChanges then
      for _, change in pairs(result.documentChanges) do
        if not change.kind or change.kind == 'rename' then
          local fname = vim.uri_to_fname(change.textDocument.uri)
          if not self.lspres[fname] then
            self.lspres[fname] = {}
          end
          for _, edit in pairs(change.edits) do
            self.lspres[fname][#self.lspres[fname] + 1] = edit.range or edit.location.range
          end
        end
      end
    end
  end
end

function rename:do_rename()
  self.new_name = vim.trim(api.nvim_get_current_line())
  self:close_rename_win()
  local current_name = vim.fn.expand('<cword>')
  local current_buf = api.nvim_get_current_buf()
  if not (self.new_name and #self.new_name > 0) or self.new_name == current_name then
    return
  end
  local current_win = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_win, self.pos)
  self:get_lsp_result()
  lsp.buf.rename(self.new_name)
  local lnum, col = unpack(self.pos)
  self.pos = nil
  api.nvim_win_set_cursor(current_win, { lnum, col + 1 })

  if not self.arg or (self.arg and self.arg ~= '++project') then
    clean_context()
    return
  end

  if fn.executable('rg') == 0 then
    return
  end

  local root_dir = lsp.get_active_clients({ bufnr = current_buf })[1].config.root_dir
  if not root_dir then
    return
  end

  local timer = uv.new_timer()
  timer:start(
    0,
    5,
    vim.schedule_wrap(function()
      if self.lspres and vim.tbl_count(self.lspres) > 0 and not timer:is_closing() then
        self:whole_project(current_name, root_dir)
        timer:stop()
        timer:close()
      end
    end)
  )
end

function rename:p_preview()
  if self.pp_winid and api.nvim_win_is_valid(self.pp_winid) then
    api.nvim_win_close(self.pp_winid, true)
  end
  local current_line = api.nvim_win_get_cursor(0)[1]
  local lines = {}
  for i, item in pairs(self.rg_data) do
    if i == current_line then
      local tbl = api.nvim_buf_get_lines(
        item.data.bufnr,
        item.data.line_number - 1,
        item.data.line_number,
        false
      )
      vim.list_extend(lines, tbl)
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

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = {
      { 'Preview', 'TitleString' },
    }
  end

  self.pp_bufnr, self.pp_winid = window.create_win_with_border({
    contents = lines,
    buftype = 'nofile',
    highlight = {
      normal = 'RenameNormal',
      border = 'RenameBorder',
    },
  }, opt)
end

function rename:popup_win(lines)
  local opt = {}
  opt.width = window.get_max_float_width()

  local max_height = math.floor(vim.o.lines * 0.3)
  opt.height = max_height > #context and max_height or #context
  opt.no_size_override = true

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = {
      { 'Files', 'TitleString' },
    }
  end

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
    if not self.confirmed then
      self.confirmed = {}
    end
    local line = api.nvim_win_get_cursor(0)[1]
    for i, data in pairs(self.confirmed) do
      for _, item in pairs(data) do
        if item.winline == line then
          table.remove(self.confirmed, i)
          api.nvim_buf_clear_namespace(0, ns, 0, -1)
          return
        end
      end
    end

    api.nvim_buf_add_highlight(0, ns, 'FinderSelection', line - 1, 0, -1)
    for i, data in pairs(self.rg_data) do
      if i == line then
        self.confirmed[#self.confirmed + 1] = data
      end
    end
  end, { buffer = self.p_bufnr, nowait = true })

  vim.keymap.set('n', config.rename.confirm, function()
    for _, item in pairs(self.confirmed or {}) do
      for _, match in pairs(item.data.submatches) do
        api.nvim_buf_set_text(
          item.data.bufnr,
          item.data.line_number - 1,
          match.start,
          item.data.line_number - 1,
          match['end'],
          { self.new_name }
        )
        api.nvim_buf_call(item.data.bufnr, function()
          vim.cmd.write()
        end)
      end
    end

    if self.p_winid and api.nvim_win_is_valid(self.p_winid) then
      api.nvim_win_close(self.p_winid, true)
    end
    if self.pp_winid and api.nvim_win_is_valid(self.pp_winid) then
      api.nvim_win_close(self.pp_winid, true)
    end
    clean_context()
  end, { buffer = self.p_bufnr, nowait = true })
end

function rename:check_in_lspres(fname, lnum)
  if not self.lspres[fname] then
    return false
  end

  for _, range in pairs(self.lspres[fname]) do
    if range.start.line + 1 == lnum then
      return true
    end
  end
  return false
end

function rename:whole_project(cur_name, root_dir)
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
    if not self.rg_data then
      self.rg_data = {}
    end

    for _, v in ipairs(parsed) do
      local path = vim.tbl_get(v, 'data', 'path', 'text')
      local lnum = vim.tbl_get(v, 'data', 'line_number')
      if v.type == 'match' and path and lnum and not self:check_in_lspres(path, lnum) then
        table.insert(self.rg_data, v)
      end
    end
    self.lspres = nil

    local lines = {}
    for _, item in pairs(self.rg_data) do
      local root_parts = vim.split(root_dir, libs.path_sep, { trimempty = true })
      local fname_parts = vim.split(item.data.path.text, libs.path_sep, { trimempty = true })
      local short = table.concat({ unpack(fname_parts, #root_parts + 1) }, libs.path_sep)
      lines[#lines + 1] = short
      local uri = vim.uri_from_fname(item.data.path.text)
      local bufnr = vim.uri_to_bufnr(uri)
      item.data.bufnr = bufnr
      if not api.nvim_buf_is_loaded(bufnr) then
        -- avoid lsp attached this buffer
        vim.opt.eventignore:append({ 'BufRead', 'BufReadPost', 'BufEnter', 'FileType' })
        fn.bufload(bufnr)
        vim.opt.eventignore:remove({ 'BufRead', 'BufReadPost', 'BufEnter', 'FileType' })
      end
    end

    if #lines == 0 then
      return
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
      res[#res + 1] = tbl
    end
  end)
end

return setmetatable(context, rename)
