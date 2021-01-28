local api= vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')

local actions = {}
local contents_bufnr = 0
local contents_winid = 0
local border_winid = 0
local bufnr = 0

local clear_data = function()
  actions = {}
  contents_winid = 0
  border_winid = 0
  bufnr = 0
end

local render_code_action_window = function (response)
  local contents = {}
  local title = config['code_action_icon'] .. 'CodeActions:'
  table.insert(contents,title)

  for _,languageServerAnswer in pairs(response) do
    for index,action in pairs(languageServerAnswer.result) do
      local action_title = '['..index..']' ..' '.. action.title
      table.insert(contents,action_title)
      table.insert(actions,action)
    end
  end

  if #contents == 1 then return end

  -- insert blank line
  local truncate_line = wrap.add_truncate_line(contents)
  table.insert(contents,2,truncate_line)

  local border_opts = {
    border = config.border_style,
    highlight = 'LspSagaCodeActionBorder'
  }
  contents_bufnr,contents_winid,_,border_winid = window.create_float_window(contents,'LspSagaCodeAction',border_opts,true)
  api.nvim_command('autocmd CursorMoved <buffer> lua require("lspsaga.codeaction").set_cursor()')

  api.nvim_buf_add_highlight(contents_bufnr,-1,"LspSagaCodeActionTitle",0,0,-1)
  api.nvim_buf_add_highlight(contents_bufnr,-1,"LspSagaCodeActionTruncateLine",1,0,-1)
  for i=1,#contents-2,1 do
    api.nvim_buf_add_highlight(contents_bufnr,-1,"LspSagaCodeActionContent",1+i,0,-1)
  end

  api.nvim_command('nnoremap <buffer><nowait><silent><cr> <cmd>lua require("lspsaga.codeaction").do_code_action()<CR>')
  api.nvim_command('nnoremap <buffer><nowait><silent>q <cmd>lua require("lspsaga.codeaction").quit_action_window()<CR>')
end

local function code_action(context)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  -- if exist diagnostic float window close it
  require('lspsaga.diagnostic').close_preview()

  bufnr = vim.fn.bufnr()
  vim.validate { context = { context, 't', true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics() }
  local params = vim.lsp.util.make_range_params()
  params.context = context
  local response = vim.lsp.buf_request_sync(0,'textDocument/codeAction', params,1000)
  if libs.result_isempty(response) then return end
  render_code_action_window(response)
end

local function range_code_action(context, start_pos, end_pos)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  bufnr = vim.fn.bufnr()
  vim.validate { context = { context, 't', true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics() }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos)
  params.context = context
  local response = vim.lsp.buf_request_sync(0,'textDocument/codeAction', params,1000)
  if libs.result_isempty(response) then return end
  render_code_action_window(response)
end

local quit_action_window = function()
  if contents_winid == 0 and border_winid == 0 then return end
  window.nvim_close_valid_window({contents_winid,border_winid})
  clear_data()
end

local set_cursor = function()
  local column = 2
  local current_line = vim.fn.line('.')

  if current_line == 1 then
    vim.fn.cursor(3,column)
  elseif current_line == 2 then
    vim.fn.cursor(2+#actions,column)
  elseif current_line == #actions + 3 then
    vim.fn.cursor(3,column)
  end
end

local function execute_command(bn,command)
  vim.lsp.buf_request(bn,'workspace/executeCommand', command)
end

local do_code_action = function()
  local number = tonumber(vim.fn.expand("<cword>"))
  local action = actions[number]

  if action.edit or type(action.command) == "table" then
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit)
    end
    if type(action.command) == "table" then
      execute_command(bufnr,action.command)
    end
  else
    execute_command(bufnr,action)
  end
  quit_action_window()
end

return {
  code_action = code_action,
  do_code_action = do_code_action,
  quit_action_window = quit_action_window,
  set_cursor = set_cursor,
  range_code_action = range_code_action
}
