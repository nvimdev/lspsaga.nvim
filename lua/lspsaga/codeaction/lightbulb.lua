local api, lsp, fn = vim.api, vim.lsp, vim.fn
local config = require('lspsaga').config
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local inrender_row = -1

local function get_name()
  return 'SagaLightBulb'
end

local namespace = api.nvim_create_namespace(get_name())
local defined = false

if not defined then
  fn.sign_define(get_name(), { text = config.ui.code_action, texthl = get_name() })
  defined = true
end

local function update_lightbulb(bufnr, row)
  api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  local name = get_name()
  pcall(fn.sign_unplace, name, { id = inrender_row, buffer = bufnr })

  if not row then
    return
  end

  if config.lightbulb.sign then
    fn.sign_place(
      row + 1,
      name,
      name,
      bufnr,
      { lnum = row + 1, priority = config.lightbulb.sign_priority }
    )
  end

  if config.lightbulb.virtual_text then
    nvim_buf_set_extmark(bufnr, namespace, row, -1, {
      virt_text = { { config.ui.code_action, name } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
  end

  inrender_row = row + 1
end

local function render(bufnr)
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local params = lsp.util.make_range_params()
  params.context = {
    diagnostics = lsp.diagnostic.get_line_diagnostics(bufnr),
  }

  lsp.buf_request_all(bufnr, 'textDocument/codeAction', params, function(results)
    if api.nvim_get_current_buf() ~= bufnr then
      return
    end

    local has_actions = false
    for _, res in ipairs(results or {}) do
      if res.result and type(res.result) == 'table' and next(res.result) ~= nil then
        has_actions = true
        break
      end
    end

    if not has_actions then
      update_lightbulb(bufnr, nil)
      return
    end

    update_lightbulb(bufnr, row)
  end)
end

local timer = vim.loop.new_timer()

local function update(buf)
  timer:start(config.lightbulb.debounce, 0, function()
    timer:stop()
    vim.schedule(function()
      render(buf)
    end)
  end)
end

local function lb_autocmd()
  local name = 'SagaLightBulb'
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup(name, { clear = true }),
    callback = function(opt)
      if not require('lspsaga.codeaction'):check_server_support_codeaction(opt.buf) then
        return
      end

      local buf = opt.buf
      local group = api.nvim_create_augroup(name .. tostring(buf), {})
      api.nvim_create_autocmd('CursorMoved', {
        group = group,
        buffer = buf,
        callback = function()
          update(buf)
        end,
      })

      api.nvim_create_autocmd('InsertEnter', {
        group = group,
        buffer = buf,
        callback = function()
          update_lightbulb(buf, nil)
        end,
      })

      api.nvim_create_autocmd('BufLeave', {
        group = group,
        buffer = buf,
        callback = function()
          update_lightbulb(buf, nil)
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

return {
  lb_autocmd = lb_autocmd,
}
