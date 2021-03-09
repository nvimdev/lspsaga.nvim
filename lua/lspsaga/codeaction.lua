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

local get_namespace = function ()
  return api.nvim_create_namespace('sagalightbulb')
end

local SIGN_GROUP = "sagalightbulb"
local SIGN_NAME = "LspSagaLightBulb"

if vim.tbl_isempty(vim.fn.sign_getdefined(SIGN_NAME)) then
    vim.fn.sign_define(SIGN_NAME, { text = config.code_action_icon, texthl = "LspDiagnosticsDefaultInformation" })
end

function Action:render_action_virtual_text(line)
  self.virt_text_cache = self.virt_text_cache or 0
  return function (_,_,response)
    local namespace = get_namespace()
    local clear_virt_text = function ()
      if self.virt_text_cache ~= 0 then
        api.nvim_buf_clear_namespace(0,namespace,self.virt_text_cache,self.virt_text_cache)
      end
    end

    if response == nil or next(response) == nil then
      clear_virt_text()
      return
    end

    self.virt_text_cache = line
    if config.code_action_prompt.virtual_text then
      local icon_with_indent = '  ' .. config.code_action_icon
      api.nvim_buf_set_extmark(0,namespace,line,-1,{
        virt_text = { {icon_with_indent,'LspSagaLightBulb'} },
        virt_text_pos = 'overlay'
      })
    end

    if config.code_action_prompt.sign then
      vim.fn.sign_place(line,SIGN_GROUP,SIGN_NAME,'%',{
        lnum = line + 1,priority = config.code_action_prompt.sign_priority
      })
    end
  end
end

function Action:action_callback()
  return function (_,_,response)
    if response == nil or vim.tbl_isempty(response) then
      print("No code actions available")
      return
    end

    local contents = {}
    local title = config['code_action_icon'] .. 'CodeActions:'
    table.insert(contents,title)

    self.actions = response
    for index,action in pairs(response) do
      local action_title = '['..index..']' ..' '.. action.title
      table.insert(contents,action_title)
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
    api.nvim_command("autocmd QuitPre <buffer> lua require('lspsaga.codeaction').quit_action_window()")

    api.nvim_buf_add_highlight(self.contents_bufnr,-1,"LspSagaCodeActionTitle",0,0,-1)
    api.nvim_buf_add_highlight(self.contents_bufnr,-1,"LspSagaCodeActionTruncateLine",1,0,-1)
    for i=1,#contents-2,1 do
      api.nvim_buf_add_highlight(self.contents_bufnr,-1,"LspSagaCodeActionContent",1+i,0,-1)
    end
    self:apply_action_keys()
  end
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

local action_call_back = function (_)
  return Action:action_callback()
end

local action_vritual_call_back = function (line)
  return Action:render_action_virtual_text(line)
end

function Action:code_action(_call_back_fn,diagnostics)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  self.bufnr = vim.fn.bufnr()
  local context =  { diagnostics = diagnostics }
  local params = vim.lsp.util.make_range_params()
  params.context = context
  local line = params.range.start.line
  local callback = _call_back_fn(line)
  vim.lsp.buf_request(0,'textDocument/codeAction', params,callback)
end

function Action:range_code_action(context, start_pos, end_pos)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  self.bufnr = vim.fn.bufnr()
  vim.validate { context = { context, 't', true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics() }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos)
  params.context = context
  local call_back = self:action_callback()
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
  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  if next(diagnostics) == nil then return end
  Action:code_action(action_call_back,diagnostics)
end

lspaction.code_action_prompt = function ()
  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  if next(diagnostics) == nil then
    local pos = api.nvim_win_get_cursor(0)[1] - 1
    if config.code_action_prompt.enable and config.code_action_prompt.virtual_text then
      if pos ~= Action.virt_text_cache and Action.virt_text_cache then
        local namespace = get_namespace()
        api.nvim_buf_clear_namespace(0,namespace,Action.virt_text_cache,Action.virt_text_cache + 1)
      end
    end

    if config.code_action_prompt and config.code_action_prompt.sign then
      if pos ~= Action.virt_text_cache and Action.virt_text_cache then
        vim.fn.sign_unplace(SIGN_GROUP,{
          id = Action.virt_text_cache,
          buffer = '%'
        })
      end
    end

    return
  end
  Action:code_action(action_vritual_call_back,diagnostics)
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
