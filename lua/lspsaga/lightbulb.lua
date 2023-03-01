local api, lsp, fn = vim.api, vim.lsp, vim.fn
local config = require('lspsaga').config
local lb = {}

local function get_hl_group()
  return 'SagaLightBulb'
end

function lb:init_sign()
  self.name = get_hl_group()
  if not self.defined_sign then
    fn.sign_define(self.name, { text = config.ui.code_action, texthl = self.name })
    self.defined_sign = true
  end
end

local function check_server_support_codeaction(bufnr)
  local libs = require('lspsaga.libs')
  local clients = lsp.get_active_clients({ bufnr = bufnr })
  for _, client in pairs(clients) do
    if not client.config.filetypes and next(config.server_filetype_map) ~= nil then
      for _, fts in pairs(config.server_filetype_map) do
        if libs.has_value(fts, vim.bo[bufnr].filetype) then
          client.config.filetypes = fts
          break
        end
      end
    end

    if
      client.supports_method('textDocument/codeAction')
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
    local icon_with_indent = '  ' .. config.ui.code_action
    pcall(api.nvim_buf_set_extmark, bufnr, namespace, line, -1, {
      virt_text = { { icon_with_indent, 'SagaLightBulb' } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
  end
end

local function generate_sign(bufnr, line)
  vim.fn.sign_place(
    line,
    lb.name,
    lb.name,
    bufnr,
    { lnum = line + 1, priority = config.lightbulb.sign_priority }
  )
end

local function _update_sign(bufnr, line)
  if vim.w.lightbulb_line == 0 then
    vim.w.lightbulb_line = 1
  end
  if vim.w.lightbulb_line ~= 0 then
    fn.sign_unplace(lb.name, { id = vim.w.lightbulb_line, buffer = bufnr })
  end

  if line then
    generate_sign(bufnr, line)
    vim.w.lightbulb_line = line
  end
end

local function render_action_virtual_text(bufnr, line, has_actions)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not has_actions then
    if config.lightbulb.virtual_text then
      _update_virtual_text(bufnr, nil)
    end
    if config.lightbulb.sign then
      _update_sign(bufnr, nil)
    end
    return
  end

  if config.lightbulb.sign then
    _update_sign(bufnr, line)
  end

  if config.lightbulb.virtual_text then
    _update_virtual_text(bufnr, line)
  end
end

local send_request = coroutine.create(function()
  local current_buf = api.nvim_get_current_buf()
  vim.w.lightbulb_line = vim.w.lightbulb_line or 0

  while true do
    local diagnostics = lsp.diagnostic.get_line_diagnostics(current_buf)
    local context = { diagnostics = diagnostics }
    local params = lsp.util.make_range_params()
    params.context = context
    local line = params.range.start.line
    lsp.buf_request_all(current_buf, 'textDocument/codeAction', params, function(results)
      local has_actions = false
      for _, res in pairs(results or {}) do
        if res.result and type(res.result) == 'table' and next(res.result) ~= nil then
          has_actions = true
          break
        end
      end

      -- if
      --   has_actions
      --   and config.code_action_lightbulb.enable
      --   and config.code_action_lightbulb.cache_code_action
      -- then
      --   codeaction.action_tuples = nil
      --   codeaction:get_clients(results)
      -- end

      render_action_virtual_text(current_buf, line, has_actions)
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

function lb.lb_autocmd()
  lb:init_sign()
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('LspSagaLightBulb', { clear = true }),
    callback = function(opt)
      local buf = opt.buf
      local group = api.nvim_create_augroup(lb.name .. tostring(buf), {})
      api.nvim_create_autocmd('CursorHold', {
        group = group,
        buffer = buf,
        callback = function()
          render_bulb(buf)
        end,
      })

      if not config.lightbulb.enable_in_insert then
        api.nvim_create_autocmd('InsertEnter', {
          group = group,
          buffer = buf,
          callback = function()
            _update_sign(buf, nil)
            _update_virtual_text(buf, nil)
          end,
        })
      end

      api.nvim_create_autocmd('BufLeave', {
        group = group,
        buffer = buf,
        callback = function()
          _update_sign(buf, nil)
          _update_virtual_text(buf, nil)
        end,
      })

      api.nvim_create_autocmd('BufDelete', {
        buffer = buf,
        once = true,
        callback = function()
          pcall(api.nvim_del_augroup_by_id, group)
        end,
      })
    end,
  })
end

return lb
