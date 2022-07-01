local api = vim.api
local lspcode = require("vim.lsp.codelens")
local wrap = require('lspsaga.wrap')
local config = require('lspsaga').config_values
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local method = 'textDocument/codeLens'

local codelens = {}

function codelens.execute_lens(lens, bufnr, client_id)
  print(vim.inspect(lens))

  local client = vim.lsp.get_client_by_id(client_id)
  local command = lens.command
  local fn = client.commands[command.command] or vim.lsp.commands[command.command]
  if fn then
    fn(command, { bufnr = bufnr, client_id = client_id })
    return
  end

  local command_provider = client.server_capabilities.executeCommandProvider
  local commands = type(command_provider) == 'table' and command_provider.commands or {}
  if not vim.tbl_contains(commands, command.command) then
    vim.notify("Error", vim.log.levels.WARN)
    return
  end
  client.request('workspace/executeCommand', command, function(...)
    local result = vim.lsp.handlers['workspace/executeCommand'](...)
    lspcode.refresh()
    return result
  end, bufnr)
end

function codelens.handler(_, result, ctx, _)
  local line = api.nvim_win_get_cursor(0)[1]
  local bufnr = api.nvim_get_current_buf()
  if codelens.options == nil then
    codelens.options = {}
  end
  local contents = {}
  local title = 'Codelens:'
  table.insert(contents, title)

  local index = 0
  for _, lens in pairs(result) do
    local lens_title = ''
    if lens.range.start.line == (line - 1) then
      index = index + 1
      codelens.options[index] = { client_id = ctx.client_id, lens = lens }
      lens_title = '[' .. index .. ']' .. ' ' .. lens.command.title
      table.insert(contents, lens_title)
    end
  end

  local truncate_line = wrap.add_truncate_line(contents)
  table.insert(contents, 2, truncate_line)

  local content_opts = {
    contents = contents,
    filetype = 'sagacodelens',
    enter = true,
    highlight = 'LspSagaCodeActionBorder'
  }

  codelens.bufnr, codelens.winid = window.create_win_with_border(content_opts)
  api.nvim_win_set_cursor(codelens.winid, { 3, 1 })
  -- TODO add highlight
  api.nvim_create_autocmd('QuitPre', {
    buffer = codelens.bufnr,
    callback = codelens.quit_lens_window
  })

  codelens.apply_action_keys()

  -- if #codelens.options == 0 then
  --   vim.notify('No executable codelens found at current line')
  -- elseif #codelens.options == 1 then
  --   local option = codelens.options[1]
  --   codelens.execute_lens(option.lens, bufnr, option.client_id)
  -- else
  --   -- TODO handler lspsaga window
  -- end
end

function codelens.quit_lens_window()
  if codelens.bufnr == 0 and codelens.winid == 0 then
    return
  end
  window.nvim_close_valid_window(codelens.winid)
  codelens.winid = 0
  codelens.bufnr = 0
  codelens.options = {} -- TODO maybe also do this other place
end

local apply_keys = libs.apply_keys("codelens")

function codelens.apply_action_keys()
  local lens = {
    ['quit_lens_window'] = config.code_action_keys.quit,
    ['do_code_lens'] = config.code_action_keys.exec,
  }
  for func, keys in pairs(lens) do
    apply_keys(func, keys)
  end
end

function codelens.do_code_lens(num)
  local number = num and tonumber(num) or tonumber(vim.fn.expand("<cword>"))
  local lens = codelens.options[number].lens
  local client_id = codelens.options[number].client_id
  codelens.execute_lens(lens, 0, client_id)
  codelens.quit_lens_window()
end

function codelens.run()
  -- local bufnr = api.nvim_get_current_buf()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params()
  }
  vim.lsp.buf_request(0, method, params, codelens.handler)
end

return codelens
