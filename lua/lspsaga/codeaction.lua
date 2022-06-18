local api= vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')
local method = 'textDocument/codeAction'


local Action = {}
Action.__index = Action

local function check_server_support_codeaction()
  local clients = vim.lsp.buf_get_clients()
    for _,client in pairs(clients) do
      if client.server_capabilities.code_action == true then
        return true
      end
    end
  return false
end

function Action:action_callback(response)
    if response == nil or vim.tbl_isempty(response) then
      print("No code actions available")
      return
    end

    local contents = {}
    local title = config['code_action_icon'] .. 'CodeActions:'
    table.insert(contents,title)

    local from_other_servers = function()
      local actions = {}
      for _,action in pairs(response) do
        self.actions[#self.actions+1] = action
        local action_title = '['..#self.actions ..']' ..' '.. action.title
        actions[#actions+1] = action_title
      end
      return actions
    end

    if self.actions and next(self.actions) ~= nil then
      local other_actions = from_other_servers()
      if next(other_actions) ~= nil then
        vim.tbl_extend('force',self.actions,other_actions)
      end
      api.nvim_buf_set_option(self.action_bufnr,'modifiable',true)
      vim.fn.append(vim.fn.line('$'),other_actions)
      vim.cmd("resize "..#self.actions+2)
      for i,_ in pairs(other_actions) do
        vim.fn.matchadd('LspSagaCodeActionContent','\\%'.. #self.actions+1+i..'l')
      end
    else
      self.actions = response
      for index,action in pairs(response) do
        local action_title = '['..index..']' ..' '.. action.title
        table.insert(contents,action_title)
      end
    end

    if #contents == 1 then return end

    -- insert blank line
    local truncate_line = wrap.add_truncate_line(contents)
    table.insert(contents,2,truncate_line)

    local content_opts = {
      contents = contents,
      filetype = 'LspSagaCodeAction',
      enter = true,
      highlight = 'LspSagaCodeActionBorder'
    }

    self.action_bufnr,self.action_winid = window.create_win_with_border(content_opts)
    api.nvim_create_autocmd('CursorMoved',{
      buffer = self.action_bufnr,
      callback = function()
        require('lspsaga.codeaction'):set_cursor()
      end
    })

    api.nvim_create_autocmd('QuitPre',{
      buffer = self.action_bufnr,
      callback = function()
        require('lspsaga.codeaction'):quit_action_window()
      end
    })

    api.nvim_buf_add_highlight(self.action_bufnr,-1,"LspSagaCodeActionTitle",0,0,-1)
    api.nvim_buf_add_highlight(self.action_bufnr,-1,"LspSagaCodeActionTruncateLine",1,0,-1)
    for i=1,#contents-2,1 do
      api.nvim_buf_add_highlight(self.action_bufnr,-1,"LspSagaCodeActionContent",1+i,0,-1)
    end
    self:apply_action_keys()
end

local apply_keys = libs.apply_keys("codeaction")

function Action:apply_action_keys()
  local actions = {
    ['quit_action_window'] = config.code_action_keys.quit,
    ['do_code_action'] = config.code_action_keys.exec
  }
  for func, keys in pairs(actions) do
    apply_keys(func, keys)
  end
end

function Action:code_action()
  self.bufnr = api.nvim_get_current_buf()
  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics(self.bufnr)
  local context =  { diagnostics = diagnostics }
  local params = vim.lsp.util.make_range_params()
  params.context = context

  vim.lsp.buf_request_all(self.bufnr,method, params,function(results)
    local response = results[1].result
    self:action_callback(response)
  end)
end

function Action:range_code_action(context, start_pos, end_pos)
  self.bufnr = api.nvim_get_current_buf()
  vim.validate { context = { context, 't', true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics(self.bufnr) }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos)
  params.context = context

  vim.lsp.buf_request_all(self.bufnr,method, params,function(results)
    local response = results[1].result
    self:action_callback(response)
  end)
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
  self.action_bufnr = 0
  self.action_winid = 0
end

function Action:quit_action_window ()
  if self.action_bufnr == 0 and self.action_winid == 0 then return end
  window.nvim_close_valid_window(self.action_winid)
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
