local api, lsp = vim.api, vim.lsp
local uv, create_autocmd, buf_clear_ns =
  vim.uv, api.nvim_create_autocmd, api.nvim_buf_clear_namespace
local config = require('lspsaga').config.lightbulb
local ui = require('lspsaga').config.ui
local buf_set_extmark = api.nvim_buf_set_extmark
local ns = api.nvim_create_namespace('SagaLightBulb')

local function clean_in_buf(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  buf_clear_ns(bufnr, ns, 0, -1)
end

local function update_lightbulb(bufnr, row)
  if not config.sign and not config.virtual_text then
    return
  end
  buf_set_extmark(bufnr, ns, row, -1, {
    virt_text = config.virtual_text and { { ui.code_action, 'SagaLightBulb' } } or nil,
    virt_text_pos = config.virtual_text and 'overlay' or nil,
    sign_text = config.sign and ui.code_action or nil,
    sign_hl_group = 'SagaLightBulb',
    priority = config.priority,
  })
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
  local lnum = api.nvim_win_get_cursor(0)[1]
  local params = lsp.util.make_range_params()
  params.context = {
    diagnostics = diagnostic_vim_to_lsp(vim.diagnostic.get(bufnr, { lnum = lnum - 1 })),
  }

  lsp.buf_request(bufnr, 'textDocument/codeAction', params, function(_, result, _)
    if
      api.nvim_get_current_buf() ~= bufnr
      or not result
      or #result == 0
      or api.nvim_win_get_cursor(0)[1] ~= lnum
      or not api.nvim_buf_is_valid(bufnr)
    then
      clean_in_buf(bufnr)
      return
    end
    update_lightbulb(bufnr, lnum - 1)
  end)
end

local function debounce()
  local timer = nil ---[[uv_timer_t]]
  local function safe_close()
    if timer and timer:is_active() and not timer:is_closing() then
      timer:close()
      timer:stop()
      timer = nil
    end
  end

  return function(bufnr)
    safe_close()
    clean_in_buf(bufnr)
    local line = api.nvim_win_get_cursor(0)[1]
    timer = assert(uv.new_timer())
    timer:start(config.debounce, 0, function()
      safe_close()
      vim.schedule(function()
        if
          api.nvim_get_current_buf() ~= bufnr
          or not api.nvim_buf_is_valid(bufnr)
          or line ~= api.nvim_win_get_cursor(0)[1]
        then
          return
        end
        render(bufnr)
      end)
    end)
  end
end

local function lb_autocmd()
  local g = api.nvim_create_augroup('SagaLightBulb', { clear = true })
  create_autocmd('LspAttach', {
    group = g,
    callback = function(opt)
      local client = lsp.get_client_by_id(opt.data.client_id)
      if
        not client
        or not client.supports_method('textDocument/codeAction')
        or vim.list_contains(config.ignore.clients, client.name)
        or vim.list_contains(config.ignore.ft, vim.bo.filetype)
      then
        return
      end
      if #api.nvim_get_autocmds({ group = g, buffer = opt.buf, event = 'CursorMoved' }) > 0 then
        return
      end
      local buf = opt.buf
      create_autocmd({ 'CursorMoved', 'InsertLeave' }, {
        group = g,
        buffer = buf,
        callback = function(args)
          debounce()(args.buf)
        end,
      })

      create_autocmd('InsertEnter', {
        group = g,
        buffer = buf,
        callback = function(args)
          clean_in_buf(args.buf)
        end,
      })

      create_autocmd('BufLeave', {
        group = g,
        buffer = buf,
        callback = function(args)
          clean_in_buf(args.buf)
        end,
      })
    end,
  })

  create_autocmd('LspDetach', {
    group = g,
    callback = function(args)
      pcall(api.nvim_del_augroup_by_name, 'SagaLightBulb' .. tostring(args.buf))
    end,
  })
end

return {
  lb_autocmd = lb_autocmd,
}
