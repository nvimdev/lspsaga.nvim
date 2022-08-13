local api = vim.api
local libs = require('lspsaga.libs')
local config = require('lspsaga').config_values
local code_action_method = 'textDocument/codeAction'
local lb = {}

local SIGN_GROUP = 'sagalightbulb'
local SIGN_NAME = 'LspSagaLightBulb'

local hl_group = 'LspSagaLightBulb'

if vim.tbl_isempty(vim.fn.sign_getdefined(SIGN_NAME)) then
  vim.fn.sign_define(SIGN_NAME, { text = config.code_action_icon, texthl = hl_group })
end

local function check_server_support_codeaction(bufnr)
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
  for _, client in pairs(clients) do
    if not client.config.filetypes and next(config.server_filetype_map) ~= nil then
      for _,fts in pairs(config.server_filetype_map) do
        if libs.has_value(fts,vim.bo[bufnr].filetype) then
          client.config.filetypes = fts
          break
        end
      end
    end

    if
      client.supports_method(code_action_method)
      and libs.has_value(client.config.filetypes, vim.bo[bufnr].filetype)
    then
      return true
    end
  end

  return false
end

local function _update_virtual_text(bufnr, line)
  local namespace = api.nvim_create_namespace('sagalightbulb')
  api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  if line then
    local icon_with_indent = '  ' .. config.code_action_icon
    api.nvim_buf_set_extmark(bufnr, namespace, line, -1, {
      virt_text = { { icon_with_indent, 'LspSagaLightBulb' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
  end
end

local sign_ns = api.nvim_create_namespace('sagalightbulb_sign')
local function generate_sign(bufnr, line)
  if vim.fn.has('nvim-0.8') == 1 then
    api.nvim_buf_set_extmark(bufnr, sign_ns, line, 0, {
      sign_text = config.code_action_icon,
      sign_hl_group = hl_group,
      priority = config.code_action_lightbulb.sign_priority,
    })
  else
    vim.fn.sign_place(
      line,
      SIGN_GROUP,
      SIGN_NAME,
      bufnr,
      { lnum = line + 1, priority = config.code_action_lightbulb.sign_priority }
    )
  end
end

local function remove_sign(bufnr)
  if vim.fn.has('nvim-0.8') == 1 then
    api.nvim_buf_clear_namespace(bufnr, sign_ns, 0, -1)
  else
    vim.fn.sign_unplace(SIGN_GROUP, { id = vim.w.lightbulb_line, buffer = bufnr })
  end
end

local function _update_sign(bufnr, line)
  if vim.w.lightbulb_line == 0 then
    vim.w.lightbulb_line = 1
  end
  if vim.w.lightbulb_line ~= 0 then
    remove_sign(bufnr)
  end

  if line then
    generate_sign(bufnr, line)
    vim.w.lightbulb_line = line
  end
end

local function render_action_virtual_text(bufnr, line, actions)
  if next(actions) == nil then
    if config.code_action_lightbulb.virtual_text then
      _update_virtual_text(bufnr, nil)
    end
    if config.code_action_lightbulb.sign then
      _update_sign(bufnr, nil)
    end
  else
    if config.code_action_lightbulb.sign then
      _update_sign(bufnr, line)
    end

    if config.code_action_lightbulb.virtual_text then
      _update_virtual_text(bufnr, line)
    end
  end
end

local send_request = coroutine.create(function()
  local current_buf = api.nvim_get_current_buf()
  vim.w.lightbulb_line = vim.w.lightbulb_line or 0

  while true do
    local diagnostics = vim.lsp.diagnostic.get_line_diagnostics(current_buf)
    local context = { diagnostics = diagnostics }
    local params = vim.lsp.util.make_range_params()
    params.context = context
    local line = params.range.start.line
    vim.lsp.buf_request_all(current_buf, code_action_method, params, function(results)
      if libs.result_isempty(results) then
        results = { { result = {} } }
      end
      local actions = {}
      for _, res in pairs(results) do
        if res.result and type(res.result) == 'table' and next(res.result) ~= nil then
          table.insert(actions, res.result)
        end
      end
      render_action_virtual_text(current_buf, line, actions)
    end)
    current_buf = coroutine.yield()
  end
end)

local render_bulb = function(bufnr)
  local has_code_action = check_server_support_codeaction(bufnr)
  if not has_code_action then
    return
  end
  coroutine.resume(send_request, bufnr)
end

function lb.action_lightbulb()
  if not libs.check_lsp_active() then
    return
  end

  local current_buf = api.nvim_get_current_buf()
  if not config.code_action_lightbulb.enable_in_insert and vim.fn.mode() == 'i' then
    _update_sign(current_buf, nil)
    _update_virtual_text(current_buf, nil)
    return
  end
  render_bulb(current_buf)
end

return lb
