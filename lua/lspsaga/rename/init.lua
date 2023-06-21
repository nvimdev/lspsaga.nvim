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

function rename:apply_action_keys()
  local modes = { 'i', 'n', 'v' }

  for i, mode in ipairs(modes) do
    util.map_keys(self.bufnr, mode, config.rename.quit, function()
      self:close_rename_win()
    end)

    if i ~= 3 then
      util.map_keys(self.bufnr, mode, config.rename.exec, function()
        self:do_rename()
      end)
    end
  end
end

function rename:find_reference()
  local bufnr = api.nvim_get_current_buf()
  local params = lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  local client = util.get_client_by_method('textDocment/references')
  if client == nil then
    return
  end

  client.request('textDocument/references', params, function(_, result)
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

function rename:lsp_rename(arg)
  local cword = fn.expand('<cword>')
  self.pos = api.nvim_win_get_cursor(0)
  self.arg = arg

  local float_opt = {
    height = 1,
    width = 30,
    enter = true,
  }

  if config.ui.title then
    float_opt.title = {
      { 'Rename', 'TitleString' },
    }
  end

  self:find_reference()

  self.bufnr, self.winid = win
    :new_float(float_opt)
    :setlines({ cword })
    :winopt('scrolloff', 0)
    :winopt('winhl', 'NormalFloat:RenameNormal,Border:RenameBorder')
    :wininfo()

  if config.rename.in_select and not self.arg then
    vim.cmd([[normal! V]])
    feedkeys('<C-g>', 'n')
  elseif self.arg then
    local mode = vim.split(self.arg, '=')[2]
    if mode == 'i' then
      vim.cmd.startinsert()
    elseif mode == 's' then
      vim.cmd([[normal! V]])
      feedkeys('<C-g>', 'n')
    end
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

local function auto_save()
  lsp.handlers['textDocument/rename'] = function(err, result, ctx)
    if err then
      vim.notify(
        '[Lspsaga] rename failed err in callback' .. table.concat(err),
        vim.log.levels.ERROR
      )
      return
    end
    local client = lsp.get_client_by_id(ctx.client_id)
    for uri, edits in pairs(result.changes or {}) do
      local bufnr = vim.uri_to_bufnr(uri)
      if api.nvim_buf_is_loaded(bufnr) then
        lsp.util.apply_text_edits(edits, bufnr, client.offset_encoding)
        api.nvim_buf_call(bufnr, function()
          vim.cmd.write()
        end)
      end
    end
  end
end

function rename:do_rename()
  self.new_name = vim.trim(api.nvim_get_current_line())
  self:close_rename_win()
  local current_name = vim.fn.expand('<cword>')
  if not (self.new_name and #self.new_name > 0) or self.new_name == current_name then
    return
  end
  local current_win = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_win, self.pos)
  if config.rename.auto_save then
    auto_save()
  end
  lsp.buf.rename(self.new_name)
  local lnum, col = unpack(self.pos)
  self.pos = nil
  api.nvim_win_set_cursor(current_win, { lnum, col + 1 })
  clean_context()
end

return setmetatable(context, rename)
