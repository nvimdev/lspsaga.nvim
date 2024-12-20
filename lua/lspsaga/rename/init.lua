local api, lsp, fn = vim.api, vim.lsp, vim.fn
local ns = api.nvim_create_namespace('LspsagaRename')
local win = require('lspsaga.window')
local util = require('lspsaga.util')
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

function rename:apply_action_keys(project)
  local modes = { 'i', 'n', 'v' }

  for i, mode in ipairs(modes) do
    util.map_keys(self.bufnr, config.rename.keys.quit, function()
      self:close_rename_win()
    end, mode)

    if i ~= 3 then
      util.map_keys(self.bufnr, config.rename.keys.exec, function()
        self:do_rename(project)
      end, mode)
    end
  end
end

function rename:find_reference()
  local bufnr = api.nvim_get_current_buf()
  local params = lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  local clients = util.get_client_by_method('textDocument/references')
  if #clients == 0 then
    return
  end

  clients[1].request('textDocument/references', params, function(_, result)
    if not result then
      return
    end

    for _, v in ipairs(result) do
      if v.range then
        local buf = vim.uri_to_bufnr(v.uri)
        local line = v.range.start.line
        local start_char = v.range.start.character
        local end_char = v.range['end'].character
        if buf == bufnr then
          api.nvim_buf_add_highlight(bufnr, ns, 'RenameMatch', line, start_char, end_char)
        end
      end
    end
  end, bufnr)
end

local feedkeys = function(keys, mode)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, true, true), mode, true)
end

local function parse_argument(args)
  local mode, project

  for _, arg in ipairs(args or {}) do
    if arg:find('mode=') then
      mode = vim.split(arg, '=', { trimempty = true })[2]
    elseif arg:find('%+%+project') then
      project = true
    end
  end
  return mode, project
end

function rename:lsp_rename(args)
  local cword = fn.expand('<cword>')
  self.pos = api.nvim_win_get_cursor(0)
  local mode, project = parse_argument(args)

  local float_opt = {
    height = 1,
    width = 30,
  }

  if config.ui.title then
    float_opt.title = {
      { 'Rename', 'SagaTitle' },
    }
  end

  self:find_reference()

  self.bufnr, self.winid = win
    :new_float(float_opt, true)
    :setlines({ cword })
    :bufopt({
      ['bufhidden'] = 'wipe',
      ['buftype'] = 'nofile',
      ['filetype'] = 'sagarename',
    })
    :winopt('scrolloff', 0)
    :winhl('RenameNormal', 'RenameBorder')
    :wininfo()

  if mode == 'i' then
    vim.cmd.startinsert()
  elseif mode == 's' or config.rename.in_select then
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

  self:apply_action_keys(project)
end

local function rename_handler(project, curname, new_name)
  ---@diagnostic disable-next-line: duplicate-set-field
  lsp.handlers['textDocument/rename'] = function(err, result, ctx)
    if err or not result then
      return
    end
    local client = lsp.get_client_by_id(ctx.client_id)
    if not client then
      return
    end
    local buffers = {}
    if result.changes and vim.tbl_count(result.changes) > 0 then
      for uri, edits in pairs(result.changes or {}) do
        local bufnr = vim.uri_to_bufnr(uri)
        lsp.util.apply_text_edits(edits, bufnr, client.offset_encoding)
        buffers[#buffers + 1] = bufnr
      end
    elseif result.documentChanges then
      for _, change in ipairs(result.documentChanges) do
        if change.textDocument and change.textDocument.uri then
          local bufnr = vim.uri_to_bufnr(change.textDocument.uri)
          lsp.util.apply_text_edits(change.edits, bufnr, client.offset_encoding)
          buffers[#buffers + 1] = bufnr
        end
      end
    end

    if config.rename.auto_save then
      vim.tbl_map(function(bufnr)
        api.nvim_buf_call(bufnr, function()
          vim.cmd('noautocmd write!')
        end)
      end, buffers)
    end

    if project then
      local ignore = vim.tbl_map(function(bufnr)
        return '!' .. vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ':t')
      end, buffers)
      for i = 1, #ignore do
        table.insert(ignore, i, '-g')
      end

      require('lspsaga.rename.project'):new({
        curname,
        new_name,
        ignore,
      })
    end
  end
end

function rename:do_rename(project)
  local new_name = vim.trim(api.nvim_get_current_line())
  self:close_rename_win()
  local current_name = vim.fn.expand('<cword>')
  if not (new_name and #new_name > 0) or new_name == current_name then
    return
  end
  local current_win = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_win, self.pos)
  rename_handler(project, current_name, new_name)

  lsp.buf.rename(new_name)
  local lnum, col = unpack(self.pos)
  self.pos = nil
  api.nvim_win_set_cursor(current_win, { lnum, col + 1 })
  clean_context()
end

return setmetatable(context, rename)
