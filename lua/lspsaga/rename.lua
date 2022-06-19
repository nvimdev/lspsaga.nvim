local lsp,util,api = vim.lsp,vim.lsp.util,vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')

local unique_name = 'textDocument-rename'
local pos = {}

local get_prompt_prefix = function()
  return config.rename_prompt_prefix..' '
end

local close_rename_win = function()
  if vim.fn.mode() == 'i' then
    vim.cmd [[stopinsert]]
  end
  local has,winid = pcall(api.nvim_win_get_var,0,unique_name)
  if has then
    window.nvim_close_valid_window(winid)
    api.nvim_win_set_cursor(0,pos)
    pos = {}
  end
end

local apply_action_keys = function(bufnr)
  local quit_key = config.rename_action_keys.quit
  local exec_key = config.rename_action_keys.exec
  local rhs_of_quit = [[<cmd>lua require('lspasga.rename').close_rename_win()<CR>]]
  local rhs_of_exec = [[<cmd>lua require('lspsaga.rename').do_rename()<CR>]]
  local opts = {nowait = true,silent = true,noremap = true}

  api.nvim_buf_set_keymap(bufnr,'i',exec_key,rhs_of_exec,opts)

  if type(quit_key) == "table" then
    for _,k in ipairs(quit_key) do
      api.nvim_buf_set_keymap(bufnr,'i',k,rhs_of_quit,opts)
    end
  else
    api.nvim_buf_set_keymap(bufnr,'i',quit_key,rhs_of_quit,opts)
  end
  api.nvim_buf_set_keymap(bufnr,'n',quit_key,rhs_of_quit,opts)
end

local lsp_rename = function()
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  -- if exist a rename float win close it.
  close_rename_win()
  pos[1],pos[2] = vim.fn.line('.'),vim.fn.col('.')

  local opts = {
    height = 1,
    width = 30,
  }

  local content_opts = {
    contents = {},
    filetype = '',
    enter = true,
    highlight = 'LspSagaRenameBorder'
  }

  local bufnr,winid = window.create_win_with_border(content_opts,opts)
  local saga_rename_prompt_prefix = api.nvim_create_namespace('lspsaga_rename_prompt_prefix')
  api.nvim_win_set_option(winid,'scrolloff',0)
  api.nvim_win_set_option(winid,'sidescrolloff',0)
  api.nvim_buf_set_option(bufnr,'modifiable',true)
  local prompt_prefix = get_prompt_prefix()
  api.nvim_buf_set_option(bufnr,'buftype','prompt')
  vim.fn.prompt_setprompt(bufnr, prompt_prefix)
  api.nvim_buf_add_highlight(bufnr, saga_rename_prompt_prefix, 'LspSagaRenamePromptPrefix', 0, 0, #prompt_prefix)
  vim.cmd [[startinsert!]]
  api.nvim_win_set_var(0,unique_name,winid)
  api.nvim_create_autocmd('QuitPre',{
    buffer = bufnr,
    once = true,
    nested = true,
    callback = function()
      require('lspsaga.rename').close_rename_win()
    end
  })
  apply_action_keys(bufnr)
end

local method = 'textDocument/rename'

local do_rename = function(options)
  options = options or {}
  local prompt_prefix = get_prompt_prefix()
  local new_name = vim.trim(vim.fn.getline('.'):sub(#prompt_prefix+1,-1))
  close_rename_win()
  local current_name = vim.fn.expand('<cword>')

  if not (new_name and #new_name > 0) or new_name == current_name then
    return
  end

  local bufnr = api.nvim_get_current_buf()

  local clients = vim.lsp.get_active_clients({
    bufnr = bufnr,
    name = options.name,
  })

  if options.filter then
    clients = vim.tbl_filter(options.filter, clients)
  end

  -- Clients must at least support rename, prepareRename is optional
  clients = vim.tbl_filter(function(client)
    return client.supports_method(method)
  end, clients)

  if #clients == 0 then
    vim.notify('[LSP] Rename, no matching language servers with rename capability.')
  end

  local try_use_client
  try_use_client = function(idx,client)
    local win = api.nvim_get_current_win()

    if not client then
      return
    end

    local function rename(name)
      local params = util.make_position_params(win, client.offset_encoding)
      params.newName = name
      local handler = client.handlers['textDocument/rename'] or vim.lsp.handlers['textDocument/rename']
      client.request('textDocument/rename', params, function(...)
        handler(...)
        try_use_client(next(clients, idx))
      end, bufnr)
    end

    if client.supports_method('textDocument/prepareRename') then
      local params = util.make_position_params(win, client.offset_encoding)
      client.request('textDocument/prepareRename', params, function(err, result)
        if err or result == nil then
          if next(clients, idx) then
            try_use_client(next(clients, idx))
          else
            local msg = err and ('Error on prepareRename: ' .. (err.message or '')) or 'Nothing to rename'
            vim.notify(msg, vim.log.levels.INFO)
          end
          return
        end

        if new_name then
          rename(new_name)
          return
        end
      end)
    else
      assert(client.supports_method('textDocument/rename'), 'Client must support textDocument/rename')
      if new_name then
        rename(new_name)
        return
      end
    end
  end
  try_use_client(next(clients))
end

return {
  lsp_rename = lsp_rename,
  do_rename = do_rename,
  close_rename_win = close_rename_win
}
