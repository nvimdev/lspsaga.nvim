local api, util, lsp = vim.api, vim.lsp.util, vim.lsp
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')
local saga_augroup = require('lspsaga').saga_augroup

local rename = {}

local method = 'textDocument/references'
local cap = 'referencesProvider'
local ns = api.nvim_create_namespace('LspsagaRename')

-- store the CursorWord highlight
local cursorword_hl = {}

function rename:close_rename_win()
  if vim.fn.mode() == 'i' then
    vim.cmd([[stopinsert]])
  end
  window.nvim_close_valid_window(self.winid)
  api.nvim_win_set_cursor(0, { self.pos[1], self.pos[2] })

  if next(cursorword_hl) ~= nil then
    pcall(api.nvim_set_hl, 0, 'CursorWord', cursorword_hl)
  end

  api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

function rename:apply_action_keys()
  local quit_key = config.rename_action_quit
  if type(quit_key) == 'string' then
    quit_key = { quit_key }
  end
  local exec_key = '<CR>'

  local modes = { 'i', 'n', 'v' }

  for i, mode in pairs(modes) do
    for _, v in ipairs(quit_key) do
      vim.keymap.set(mode, v, function()
        self:close_rename_win()
      end, { buffer = self.bufnr })
    end
    if i ~= 3 then
      vim.keymap.set(mode, exec_key, function()
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
  local client = libs.get_client_by_cap(cap)
  if client == nil then
    return
  end

  client.request(method, params, function(_, result)
    if not result then
      return
    end

    -- if user has highlight cusorword plugin remove the highlight before
    -- and restore it when rename done
    if vim.fn.hlexists('CursorWord') == 1 then
      if next(cursorword_hl) == nil then
        local cursorword_color = api.nvim_get_hl_by_name('CursorWord', true)
        cursorword_hl = cursorword_color
      end
      api.nvim_set_hl(0, 'CursorWord', { fg = 'none', bg = 'none' })
    end

    for _, v in pairs(result) do
      if v.range then
        local line = v.range.start.line
        local start_char = v.range.start.character
        local end_char = v.range['end'].character
        api.nvim_buf_add_highlight(bufnr, ns, 'LspSagaRenameMatch', line, start_char, end_char)
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

---@private
local function get_text_at_range(range, offset_encoding)
  local bufnr = api.nvim_get_current_buf()
  return api.nvim_buf_get_text(
    bufnr,
    range.start.line,
    util._get_line_byte_from_position(bufnr, range.start, offset_encoding),
    range['end'].line,
    util._get_line_byte_from_position(bufnr, range['end'], offset_encoding),
    {}
  )[1]
end

local function do_prepare_rename(f)
  local pre_method = 'textDocument/prepareRename'

  local client
  local clients = lsp.get_active_clients({ buffer = 0 })
  for _, c in pairs(clients) do
    local filetypes = c.filetypes
    if
      c.supports_method(pre_method)
      and filetypes
      and vim.tbl_contains(filetypes, vim.bo.filetype)
    then
      client = c
      break
    end
  end
  local current_word = vim.fn.expand('<cword>')

  if client then
    local current_win = api.nvim_get_current_win()
    local params = util.make_position_params(current_win, client.offset_encoding)
    client.request(pre_method, params, function(err, result)
      if err or result == nil then
        local msg = err and ('Error on prepareRename: ' .. (err.message or ''))
          or 'Nothing to rename'
        vim.notify(msg, vim.log.levels.INFO)
        return
      end

      if result.placeholder then
        current_word = result.placeholder
      elseif result.start then
        current_word = get_text_at_range(result, client.offset_encoding)
      elseif result.range then
        current_word = get_text_at_range(result.range, client.offset_encoding)
      end
      f(current_word)
    end, 0)
  else
    f(current_word)
  end
end

function rename:lsp_rename()
  if not libs.check_lsp_active(false) then
    return
  end

  if not support_change() then
    vim.notify('Current is builtin or keyword,you can not rename it', vim.log.levels.WARN)
    return
  end

  local try_to_rename = function(current_word)
    self.pos = api.nvim_win_get_cursor(0)

    local opts = {
      height = 1,
      width = 30,
    }

    local content_opts = {
      contents = {},
      filetype = 'sagarename',
      enter = true,
      highlight = 'LspSagaRenameBorder',
    }

    self:find_reference()

    self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
    self:set_local_options()
    api.nvim_buf_set_lines(self.bufnr, -2, -1, false, { current_word })

    if config.rename_in_select then
      vim.cmd([[normal! V]])
      feedkeys('<C-g>', 'n')
    end

    local quit_id, close_unfocus
    quit_id = api.nvim_create_autocmd('QuitPre', {
      group = saga_augroup,
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
      group = saga_augroup,
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

  do_prepare_rename(try_to_rename)
end

function rename:do_rename()
  local new_name = vim.trim(api.nvim_get_current_line())
  self:close_rename_win()
  local current_name = vim.fn.expand('<cword>')
  if not (new_name and #new_name > 0) or new_name == current_name then
    return
  end
  local current_win = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_win, self.pos)
  lsp.buf.rename(new_name)
  api.nvim_win_set_cursor(current_win, { self.pos[1], self.pos[2] + 1 })
  self.pos = nil
end

return rename
