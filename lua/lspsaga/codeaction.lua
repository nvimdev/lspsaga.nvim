local api= vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')

local Action = {}
Action.__index = Action

function Action:register_clearn_fn(fn)
  self._clear_fn = {}
  table.insert(self._clear_fn,fn)
end

function Action:clear_tmp_data()
  for _,fn in ipairs(self._clear_fn) do
    fn()
  end
end

function Action:action_callback(response)
  if response == nil or vim.tbl_isempty(response) then
    print("No code actions available")
    return
  end
  local contents = {}
  local title = config['code_action_icon'] .. 'CodeActions:'
  table.insert(contents,title)
  self.actions = {}

  for _,languageServerAnswer in pairs(response) do
    for index,action in pairs(languageServerAnswer.result) do
      local action_title = '['..index..']' ..' '.. action.title
      table.insert(contents,action_title)
      table.insert(self.actions,action)
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

  local content_opts = {
    contents = contents,
    filetype = 'LspSagaCodeActionTitle',
    enter = true
  }

  self.contents_bufnr,self.contents_winid,_,self.border_winid = window.create_float_window(content_opts,border_opts)
  api.nvim_command('autocmd CursorMoved <buffer> lua require("lspsaga.codeaction").set_cursor()')

  api.nvim_buf_add_highlight(self.contents_bufnr,-1,"LspSagaCodeActionTitle",0,0,-1)
  api.nvim_buf_add_highlight(self.contents_bufnr,-1,"LspSagaCodeActionTruncateLine",1,0,-1)
  for i=1,#contents-2,1 do
    api.nvim_buf_add_highlight(self.contents_bufnr,-1,"LspSagaCodeActionContent",1+i,0,-1)
  end
  self:apply_action_keys()
end

local function call_back(_,_,response)
  Action:action_callback(response)
end

function Action:apply_action_keys()
  local quit_key = config.code_action_keys.quit
  local exec_key = config.code_action_keys.exec
  api.nvim_command('nnoremap <buffer><nowait><silent>'..exec_key..' <cmd>lua require("lspsaga.codeaction").do_code_action()<CR>')
  api.nvim_command('nnoremap <buffer><nowait><silent>'..quit_key..' <cmd>lua require("lspsaga.codeaction").quit_action_window()<CR>')
end

function Action:code_action(context)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  -- if exist diagnostic float window close it
  require('lspsaga.diagnostic').close_preview()

  self.bufnr = vim.fn.bufnr()
  vim.validate { context = { context, 't', true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics() }
  local params = vim.lsp.util.make_range_params()
  params.context = context
  vim.lsp.buf_request(0,'textDocument/codeAction', params,call_back)
end

function Action:range_code_action(context, start_pos, end_pos)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  self.bufnr = vim.fn.bufnr()
  vim.validate { context = { context, 't', true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics() }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos)
  params.context = context
  vim.lsp.buf_request(0,'textDocument/codeAction', params,call_back)
end

function Action:set_cursor ()
  local column = 2
  local current_line = vim.fn.line('.')

  if current_line == 1 then
    vim.fn.cursor(3,column)
  elseif current_line == 2 then
    vim.fn.cursor(2+#self.actions,column)
  elseif current_line == #self.actions + 3 then
    vim.fn.cursor(3,column)
  end
end

local function lsp_execute_command(bn,command)
  vim.lsp.buf_request(bn,'workspace/executeCommand', command)
end

function Action:do_code_action()
  local number = tonumber(vim.fn.expand("<cword>"))
  local action = self.actions[number]

  if action.edit or type(action.command) == "table" then
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit)
    end
    if type(action.command) == "table" then
      lsp_execute_command(self.bufnr,action.command)
    end
  else
    lsp_execute_command(self.bufnr,action)
  end
  self:quit_action_window()
end

function Action:clear_tmp_data()
  self.actions = {}
  self.bufnr = 0
  self.contents_bufnr = 0
  self.contents_winid = 0
  self.border_winid = 0
end

function Action:quit_action_window ()
  if self.contents_winid == 0 and self.border_winid == 0 then return end
  window.nvim_close_valid_window({self.contents_winid,self.border_winid})
  self:clear_tmp_data()
end

local lspaction = {}

lspaction.code_action = function()
  Action:code_action()
end

lspaction.do_code_action = function ()
  Action:do_code_action()
end

lspaction.quit_action_window = function()
  Action:quit_action_window()
end

lspaction.range_code_action = function ()
  Action:range_code_action()
end

lspaction.set_cursor = function ()
  Action:set_cursor()
end

return lspaction
