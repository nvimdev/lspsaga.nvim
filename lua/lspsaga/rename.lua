local api,util,lsp = vim.api,vim.lsp.util,vim.lsp
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')
local saga_augroup = require('lspsaga').saga_augroup

local unique_name = 'textDocument-rename'
local pos = {}

local method = 'textDocument/references'
local ns = api.nvim_create_namespace('LspsagaRename')

-- store the CursorWord highlight
local cursorword_hl = {}

local close_rename_win = function()
  if vim.fn.mode() == 'i' then
    vim.cmd [[stopinsert]]
  end
  local has,winid = pcall(api.nvim_win_get_var,0,unique_name)
  if has then
    window.nvim_close_valid_window(winid)
  end
  api.nvim_win_set_cursor(0,{pos[1],pos[2]})

  if next(cursorword_hl) ~= nil then
    api.nvim_set_hl(0,'CursorWord',cursorword_hl)
  end

  api.nvim_buf_clear_namespace(0,ns,0,-1)
end

local apply_action_keys = function(bufnr)
  local quit_key = config.rename_action_quit
  local exec_key = '<CR>'
  local rhs_of_quit = [[<cmd>lua require('lspsaga.rename').close_rename_win()<CR>]]
  local rhs_of_exec = [[<cmd>lua require("lspsaga.rename").do_rename()<CR>]]
  local opts = {nowait = true,silent = true,noremap = true}

  api.nvim_buf_set_keymap(bufnr,'i',exec_key,rhs_of_exec,opts)
  api.nvim_buf_set_keymap(bufnr,'n',exec_key,rhs_of_exec,opts)

  api.nvim_buf_set_keymap(bufnr,'i',quit_key,rhs_of_quit,opts)
  api.nvim_buf_set_keymap(bufnr,'n',quit_key,rhs_of_quit,opts)
  api.nvim_buf_set_keymap(bufnr,'v',quit_key,rhs_of_quit,opts)
end

local set_local_options = function()
  local opt_locals = {
    scrolloff = 0,
    sidescrolloff = 0,
    modifiable = true,
  }

  for opt,val in pairs(opt_locals) do
    vim.opt_local[opt] = val
  end
end

local find_reference = function()
  local bufnr = api.nvim_get_current_buf()
  local params = util.make_position_params()
  params.context = {includeDeclaration = true}
  lsp.buf_request_all(bufnr,method,params,function(response)
    if libs.result_isempty(response) then return end

  -- if user has highlight cusorword plugin remove the highlight before
  -- and restore it when rename done
    if vim.fn.hlexists('CursorWord') == 1 then
      if next(cursorword_hl) == nil then
        local cursorword_color = api.nvim_get_hl_by_name('CursorWord',true)
        cursorword_hl = cursorword_color
      end
      api.nvim_set_hl(0,'CursorWord',{fg ='none',bg = 'none'})
    end

    if next(response) == nil or type(response) ~= 'table' then return end

    for _,res in pairs(response) do
      for _,v in pairs(res.result) do
        if v.range then
          local line = v.range.start.line
          local start_char = v.range.start.character
          local end_char = v.range['end'].character
          api.nvim_buf_add_highlight(bufnr,ns,'LspSagaRenameMatch',line,start_char,end_char)
        end
      end
    end
  end)
end

local feedkeys = function(keys,mode)
  api.nvim_feedkeys(
    api.nvim_replace_termcodes(keys, true, true, true),
    mode,
    true
  )
end

local lsp_rename = function()
  if not libs.check_lsp_active() then
    return
  end

--   local current_buf = api.nvim_get_current_buf()
  local current_win = api.nvim_get_current_win()
  local current_word = vim.fn.expand('<cword>')
  pos = api.nvim_win_get_cursor(current_win)

  local opts = {
    height = 1,
    width = 30,
  }

  local content_opts = {
    contents = {},
    filetype = '',
    enter = true,
    highlight = 'LspSagaRenameBorder'
  }

  find_reference()

  local bufnr,winid = window.create_win_with_border(content_opts,opts)
  set_local_options()
  api.nvim_buf_set_lines(bufnr,-2,-1,false,{current_word})

  vim.cmd [[normal! viw]]
  feedkeys('<C-g>','v')

  api.nvim_win_set_var(0,unique_name,winid)
  api.nvim_create_autocmd('QuitPre',{
    group = saga_augroup,
    buffer = bufnr,
    once = true,
    nested = true,
    callback = function()
      require('lspsaga.rename').close_rename_win()
    end
  })
  apply_action_keys(bufnr)
end

local function do_rename()
  local new_name = vim.trim(api.nvim_get_current_line())
  close_rename_win()
  local current_name = vim.fn.expand('<cword>')
  if not (new_name and #new_name > 0) or new_name == current_name then
    return
  end
  local current_win = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_win,pos)
  vim.lsp.buf.rename(new_name)
  api.nvim_win_set_cursor(current_win,{pos[1],pos[2]+1})
  pos = {}
end

return {
  lsp_rename = lsp_rename,
  close_rename_win = close_rename_win,
  do_rename = do_rename
}
