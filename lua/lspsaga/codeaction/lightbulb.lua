local api, lsp, fn = vim.api, vim.lsp, vim.fn
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local config = require('lspsaga').config
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local inrender_row = -1
local inrender_buf = nil

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
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end
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
  inrender_buf = bufnr
end

local function severity_vim_to_lsp(severity)
  if type(severity) == 'string' then
    severity = vim.diagnostic.severity[severity]
  end
  return severity
end

--- @param diagnostic vim.Diagnostic
--- @return lsp.DiagnosticTag[]?
local function tags_vim_to_lsp(diagnostic)
  if not diagnostic._tags then
    return
  end

  local tags = {} --- @type lsp.DiagnosticTag[]
  if diagnostic._tags.unnecessary then
    tags[#tags + 1] = vim.lsp.protocol.DiagnosticTag.Unnecessary
  end
  if diagnostic._tags.deprecated then
    tags[#tags + 1] = vim.lsp.protocol.DiagnosticTag.Deprecated
  end
  return tags
end

local function diagnostic_vim_to_lsp(diagnostics)
  ---@param diagnostic vim.Diagnostic
  ---@return lsp.Diagnostic
  return vim.tbl_map(function(diagnostic)
    local user_data = diagnostic.user_data or {}
    if user_data.lsp and not vim.tbl_isempty(user_data.lsp) and user_data.lsp.range then
      return user_data.lsp
    end
    return {
      range = {
        start = {
          line = diagnostic.lnum + 1,
          character = diagnostic.col,
        },
        ['end'] = {
          line = diagnostic.end_lnum + 1,
          character = diagnostic.end_col,
        },
      },
      severity = severity_vim_to_lsp(diagnostic.severity),
      message = diagnostic.message,
      source = diagnostic.source,
      code = diagnostic.code,
      tags = tags_vim_to_lsp(diagnostic),
    }
  end, diagnostics)
end

local function render(bufnr)
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local client = vim.lsp.get_clients({ bufnr = bufnr })[1]
  local offset_encoding = client and client.offset_encoding or 'utf-16'
  local params = lsp.util.make_range_params(0, offset_encoding)
  params.context = {
    diagnostics = diagnostic_vim_to_lsp(vim.diagnostic.get(bufnr, { lnum = row })),
  }

  lsp.buf_request(bufnr, 'textDocument/codeAction', params, function(_, result, _)
    if api.nvim_get_current_buf() ~= bufnr then
      return
    end

    if result and #result > 0 then
      update_lightbulb(bufnr, row)
    else
      update_lightbulb(bufnr, nil)
    end
  end)
end

local timer = assert(uv.new_timer())

local function update(buf)
  timer:stop()
  update_lightbulb(inrender_buf)
  timer:start(config.lightbulb.debounce, 0, function()
    timer:stop()
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) and api.nvim_get_current_buf() == buf then
        render(buf)
      end
    end)
  end)
end

local function lb_autocmd()
  local name = 'SagaLightBulb'
  local g = api.nvim_create_augroup(name, { clear = true })
  api.nvim_create_autocmd('LspAttach', {
    group = g,
    callback = function(opt)
      local client = lsp.get_client_by_id(opt.data.client_id)
      if not client then
        return
      end
      if not client.supports_method('textDocument/codeAction') then
        return
      end
      if vim.tbl_contains(config.lightbulb.ignore.clients, client.name) then
        return
      end
      if vim.tbl_contains(config.lightbulb.ignore.ft, vim.bo.filetype) then
        return
      end

      local buf = opt.buf
      local group_name = name .. tostring(buf)
      local ok = pcall(api.nvim_get_autocmds, { group = group_name })
      if ok then
        return
      end
      local group = api.nvim_create_augroup(group_name, { clear = true })
      api.nvim_create_autocmd('CursorMoved', {
        group = group,
        buffer = buf,
        callback = function(args)
          update(args.buf)
        end,
      })

      if not config.lightbulb.enable_in_insert then
        api.nvim_create_autocmd('InsertEnter', {
          group = group,
          buffer = buf,
          callback = function(args)
            update_lightbulb(args.buf, nil)
          end,
        })
      end

      api.nvim_create_autocmd('BufLeave', {
        group = group,
        buffer = buf,
        callback = function(args)
          update_lightbulb(args.buf, nil)
        end,
      })
    end,
  })

  api.nvim_create_autocmd('LspDetach', {
    group = g,
    callback = function(args)
      pcall(api.nvim_del_augroup_by_name, 'SagaLightBulb' .. tostring(args.buf))
    end,
  })
end

return {
  lb_autocmd = lb_autocmd,
}
