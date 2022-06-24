local api = vim.api
local libs = require('lspsaga.libs')
local config = require('lspsaga').config_values
local method = 'textDocument/codeAction'
local lb = {}

local SIGN_GROUP = "sagalightbulb"
local SIGN_NAME = "LspSagaLightBulb"

if vim.tbl_isempty(vim.fn.sign_getdefined(SIGN_NAME)) then
  vim.fn.sign_define(SIGN_NAME, { text = config.code_action_icon, texthl = "LspSagaLightBulb" })
end

local function check_server_support_codeaction()
  local clients = vim.lsp.buf_get_clients()
    for _,client in pairs(clients) do
      if client.supports_method(method) then
        return true
      end
    end
  return false
end

local function _update_virtual_text(line)
  local namespace = api.nvim_create_namespace('sagalightbulb')
  api.nvim_buf_clear_namespace(0, namespace, 0, -1)

  if line then
    local icon_with_indent = '  ' .. config.code_action_icon
    api.nvim_buf_set_extmark(0,namespace,line,-1,{
        virt_text = { {icon_with_indent,'LspSagaLightBulb'} },
        virt_text_pos = 'overlay',
        hl_mode = "combine"
      })
  end
end

local function _update_sign(line)

  local current_buf = api.nvim_get_current_buf()
  if vim.w.lightbulb_line == 0 then vim.w.lightbulb_line = 1 end
  if vim.w.lightbulb_line ~= 0 then
    vim.fn.sign_unplace(
      SIGN_GROUP, { id = vim.w.lightbulb_line, buffer = current_buf }
    )
  end

  if line then
    vim.fn.sign_place(
      line, SIGN_GROUP, SIGN_NAME, current_buf,
      { lnum = line + 1, priority = config.code_action_lightbulb.sign_priority }
    )
    vim.w.lightbulb_line = line
  end
end

local function render_action_virtual_text(line,diagnostics,actions)
  if next(actions) == nil and next(diagnostics) == nil then
    if config.code_action_lightbulb.virtual_text then
      _update_virtual_text(nil)
    end
    if config.code_action_lightbulb.sign then
      _update_sign(nil)
    end
  elseif next(actions) ~= nil and next(diagnostics) == nil then
    if config.code_action_lightbulb.sign then
      _update_sign(line)
    end

    if config.code_action_lightbulb.virtual_text then
        _update_virtual_text(line)
    end
  elseif next(actions) ~= nil and next(diagnostics) ~= nil then
    if config.code_action_lightbulb.sign then
      _update_sign(line)
    end

    if config.code_action_lightbulb.virtual_text then
        _update_virtual_text(line)
    end
  else
    if config.code_action_lightbulb.virtual_text then
      _update_virtual_text(nil)
    end
    if config.code_action_lightbulb.sign then
      _update_sign(nil)
    end
  end
end

local send_request  = coroutine.create(function()
  local current_buf = api.nvim_get_current_buf()
  vim.w.lightbulb_line = vim.w.lightbulb_line or 0

  while true do
    local diagnostics = vim.lsp.diagnostic.get_line_diagnostics(current_buf)
    local context =  { diagnostics = diagnostics }
    local params = vim.lsp.util.make_range_params()
    params.context = context
    local line = params.range.start.line
    local response = vim.lsp.buf_request_sync(current_buf,method, params,1000)
    if libs.result_isempty(response) then
      response = { { result = {}}}
    end

    local actions = {}
    for _,res in pairs(response) do
      if res.result and type(res.result) == 'table' and next(res.result) ~= nil then
        table.insert(actions,res.result)
      end
    end
    current_buf = coroutine.yield(line,diagnostics,actions)
  end
end)

local render_bulb  = function()
  local current_buf = api.nvim_get_current_buf()
  local _,line,diagnostics,actions = coroutine.resume(send_request,current_buf)
  render_action_virtual_text(line,diagnostics,actions)
end

function lb.action_lightbulb()
  local has_code_action = check_server_support_codeaction()
  if not has_code_action then return end
  render_bulb()
end

return lb
