local lsp,util,api = vim.lsp,vim.lsp.util,vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')

local unique_name = 'textDocument-rename'
local pos = {}

local close_rename_win = function()
  local has,winids = pcall(api.nvim_win_get_var,0,unique_name)
  if has then
    window.nvim_close_valid_window(winids)
    api.nvim_command('stopinsert')
    api.nvim_win_set_cursor(0,pos)
    pos = {}
  end
end

local rename = function()
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  -- if exist a rename float win close it.
  close_rename_win()
  pos[1],pos[2] = vim.fn.getpos('.')[2],vim.fn.getpos('.')[3]
  local opts = {
    height = config.rename_row,
    width = 20,
    border_text = ''
  }
  local border_opts = {
    border = config.border_style,
    title = 'New name'
  }
  local cb,cw,_,bw = window.create_float_window({},'',border_opts,true,opts)

  api.nvim_buf_set_option(cb,'modifiable',true)
  api.nvim_command('startinsert')
  api.nvim_win_set_var(0,unique_name,{cw,bw})
  api.nvim_command('inoremap <buffer><silent><cr> <cmd>lua require("lspsaga.rename").do_rename()<CR>')
  api.nvim_command('nnoremap <buffer><silent>q <cmd>lua require("lspsaga.rename").close_rename_win()<CR>')
  api.nvim_command("autocmd QuitPre <buffer> lua require('lspsaga.rename').close_rename_win()")
end

local do_rename = function()
  local new_name = vim.fn.getline('.')
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

