local lsp,util,api = vim.lsp,vim.lsp.util,vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')

local unique_name = 'textDocument-rename'
local pos = {}

local get_prompt_prefix = function()
  return config.rename_prompt_prefix..' '
end

local close_rename_win = function()
  if vim.fn.mode() == 'i' then
    vim.cmd [[stopinsert]]
  end
  local has,winids = pcall(api.nvim_win_get_var,0,unique_name)
  if has then
    window.nvim_close_valid_window(winids)
    api.nvim_win_set_cursor(0,pos)
    pos = {}
  end
end

local rename = function()
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  -- if exist a rename float win close it.
  close_rename_win()
  pos[1],pos[2] = vim.fn.line('.'),vim.fn.col('.')

  local opts = {
    height = 1,
    width = 30,
  }

  local border_opts = {
    border = config.border_style,
    title = 'New name',
    highlight = 'LspSagaRenameBorder'
  }

  local content_opts = {
    contents = {},
    filetype = '',
    enter = true
  }

  local cb,cw,_,bw = window.create_float_window(content_opts,border_opts,opts)
  local saga_rename_prompt_prefix = api.nvim_create_namespace('lspsaga_rename_prompt_prefix')
  api.nvim_win_set_option(cw,'scrolloff',0)
  api.nvim_win_set_option(cw,'sidescrolloff',0)
  api.nvim_buf_set_option(cb,'modifiable',true)
  local prompt_prefix = get_prompt_prefix()
  api.nvim_buf_set_option(cb,'buftype','prompt')
  vim.fn.prompt_setprompt(cb, prompt_prefix)
  api.nvim_buf_add_highlight(cb, saga_rename_prompt_prefix, 'LspSagaRenamePromptPrefix', 0, 0, #prompt_prefix)
  vim.cmd [[startinsert!]]
  api.nvim_win_set_var(0,unique_name,{cw,bw})
  api.nvim_command('inoremap <buffer><silent><cr> <cmd>lua require("lspsaga.rename").do_rename()<CR>')
  api.nvim_command('nnoremap <buffer><silent>q <cmd>lua require("lspsaga.rename").close_rename_win()<CR>')
  api.nvim_command('inoremap <buffer><silent><C-c> <cmd>lua require("lspsaga.rename").close_rename_win()<CR>')
  api.nvim_command("autocmd QuitPre <buffer> ++nested ++once :silent lua require('lspsaga.rename').close_rename_win()")
end

local do_rename = function()
  local prompt_prefix = get_prompt_prefix()
  local new_name = vim.trim(vim.fn.getline('.'):sub(#prompt_prefix+1,-1))
  close_rename_win()
  local params = util.make_position_params()
  local current_name = vim.fn.expand('<cword>')
  if not (new_name and #new_name > 0) or new_name == current_name then
    return
  end
  params.newName = new_name
  lsp.buf_request(0,'textDocument/rename', params)
end

return {
  rename = rename,
  do_rename = do_rename,
  close_rename_win = close_rename_win
}
