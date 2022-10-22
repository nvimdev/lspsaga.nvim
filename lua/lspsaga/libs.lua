local api = vim.api
local libs = {}
local window = require('lspsaga.window')
local server_filetype_map = require('lspsaga').config_values.server_filetype_map
local saga_augroup = require('lspsaga').saga_augroup

function libs.is_windows()
  return vim.loop.os_uname().sysname:find('Windows', 1, true) and true
end

libs.path_sep = libs.is_windows() and '\\' or '/'

function libs.get_home_dir()
  if libs.is_windows() then
    return os.getenv('USERPROFILE')
  end
  return os.getenv('HOME')
end

-- check index in table
function libs.has_key(tab, idx)
  for index, _ in pairs(tab) do
    if index == idx then
      return true
    end
  end
  return false
end

function libs.has_value(filetypes, val)
  if type(filetypes) == 'table' then
    for _, v in pairs(filetypes) do
      if v == val then
        return true
      end
    end
  elseif type(filetypes) == 'string' then
    if filetypes == val then
      return true
    end
  end
  return false
end

function libs.nvim_create_keymap(definitions)
  for _, def in pairs(definitions) do
    local mode, lhs, rhs, opts = def[1], def[2], def[3], def[4]

    if type(lhs) == 'table' then
      for _, key in ipairs(lhs) do
        vim.keymap.set(mode, key, rhs, opts)
      end
    else
      vim.keymap.set(mode, lhs, rhs, opts)
    end
  end
end

function libs.check_lsp_active(silent)
  silent = silent or true
  local current_buf = api.nvim_get_current_buf()
  local active_clients = vim.lsp.get_active_clients({ buffer = current_buf })
  if next(active_clients) == nil then
    if not silent then
      vim.notify('[LspSaga] Current buffer does not have any lsp server')
    end
    return false
  end
  return true
end

function libs.merge_table(t1, t2)
  for _, v in pairs(t2) do
    table.insert(t1, v)
  end
end

function libs.get_lsp_root_dir()
  if not libs.check_lsp_active() then
    return
  end

  local clients = vim.lsp.get_active_clients()
  for _, client in pairs(clients) do
    if client.config.filetypes and client.config.root_dir then
      if libs.has_value(client.config.filetypes, vim.bo.filetype) then
        return client.config.root_dir
      end
    else
      for name, fts in pairs(server_filetype_map) do
        for _, ft in pairs(fts) do
          if ft == vim.bo.filetype and client.config.name == name and client.config.root_dir then
            return client.config.root_dir
          end
        end
      end
    end
  end
  return nil
end

function libs.get_config_lsp_filetypes()
  local ok, lsp_config = pcall(require, 'lspconfig.configs')
  if not ok then
    return
  end

  local filetypes = {}
  for _, config in pairs(lsp_config) do
    if config.filetypes then
      for _, ft in pairs(config.filetypes) do
        table.insert(filetypes, ft)
      end
    end
  end

  if next(server_filetype_map) ~= nil then
    for _, fts in pairs(server_filetype_map) do
      if type(fts) == 'table' then
        for _, ft in pairs(fts) do
          table.insert(filetypes, ft)
        end
      elseif type(fts) == 'string' then
        table.insert(filetypes, fts)
      end
    end
  end

  return filetypes
end

function libs.close_preview_autocmd(bufnr, winids, events)
  api.nvim_create_autocmd(events, {
    group = saga_augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      window.nvim_close_valid_window(winids)
    end,
  })
end

function libs.disable_move_keys(bufnr)
  local keys = { 'h', 'ge', 'e', '0', '$', 'l', 'w', 'b', '<Bs>' }
  local opts = { nowait = true, noremap = true, silent = true }
  for _, key in pairs(keys) do
    api.nvim_buf_set_keymap(bufnr, 'n', key, '', opts)
  end
end

function libs.find_buffer_by_filetype(ft)
  local all_bufs = vim.fn.getbufinfo()
  local filetype = ''
  for _, bufinfo in pairs(all_bufs) do
    filetype = api.nvim_buf_get_option(bufinfo['bufnr'], 'filetype')

    if type(ft) == 'table' and libs.has_value(ft, filetype) then
      return true, bufinfo['bufnr']
    end

    if filetype == ft then
      return true, bufinfo['bufnr']
    end
  end

  return false, nil
end

function libs.removeElementByKey(tbl, key)
  local tmp = {}

  for i in pairs(tbl) do
    table.insert(tmp, i)
  end

  local newTbl = {}
  local i = 1
  while i <= #tmp do
    local val = tmp[i]
    if val == key then
      table.remove(tmp, i)
    else
      newTbl[val] = tbl[val]
      i = i + 1
    end
  end
  return newTbl
end

function libs.generate_empty_table(length)
  local empty_tbl = {}
  if length == 0 then
    return empty_tbl
  end

  for _ = 1, length do
    table.insert(empty_tbl, '   ')
  end
  return empty_tbl
end

function libs.add_client_filetypes(client, fts)
  if not client.config.filetypes then
    client.config.filetypes = fts
  end
end

-- get client by capabilities
function libs.get_client_by_cap(caps)
  local client_caps = {
    ['string'] = function(instance)
      libs.add_client_filetypes(instance, { vim.bo.filetype })
      if
        instance.server_capabilities[caps]
        and libs.has_value(instance.config.filetypes, vim.bo.filetype)
      then
        return instance
      end
      return nil
    end,
    ['table'] = function(instance)
      libs.add_client_filetypes(instance, { vim.bo.filetype })
      if
        instance.server_capabilities[caps[1]]
        and instance.server_capabilities[caps[2]]
        and libs.has_value(instance.config.filetypes, vim.bo.filetype)
      then
        return instance
      end
      return nil
    end,
  }

  local clients = vim.lsp.buf_get_clients()
  local client
  for _, instance in pairs(clients) do
    client = client_caps[type(caps)](instance)
    if client ~= nil then
      break
    end
  end
  return client
end

local function feedkeys(key)
  local k = api.nvim_replace_termcodes(key, true, false, true)
  api.nvim_feedkeys(k, 'x', false)
end

function libs.scroll_in_preview(bufnr, preview_winid)
  local config = require('lspsaga').config_values
  if preview_winid and api.nvim_win_is_valid(preview_winid) then
    vim.keymap.set('n', config.scroll_in_preview.scroll_down, function()
      api.nvim_win_call(preview_winid, function()
        feedkeys('<C-d>')
      end)
    end, { buffer = bufnr })

    vim.keymap.set('n', config.scroll_in_preview.scroll_up, function()
      api.nvim_win_call(preview_winid, function()
        feedkeys('<C-u>')
      end)
    end, { buffer = bufnr })
  end
end

function libs.delete_scroll_map(bufnr)
  local config = require('lspsaga').config_values
  vim.keymap.del('n', config.scroll_in_preview.scroll_down, { buffer = bufnr })
  vim.keymap.del('n', config.scroll_in_preview.scroll_up, { buffer = bufnr })
end

function libs.async(routine, ...)
  local f = coroutine.create(function(await, ...)
    routine(await, ...)
  end)
  local await = { error = nil, result = nil, completed = false }
  local complete = function(arg, err)
    await.result = arg
    await.error = err
    await.completed = true
    coroutine.resume(f)
  end
  await.resolve = function(arg)
    complete(arg, nil)
  end
  await.reject = function(err)
    complete(nil, err)
  end
  await.__call = function(self, wait, ...)
    local lastResult = self.result
    self.completed = false
    wait(self, ...)
    if not self.completed then
      coroutine.yield(f, ...)
    end
    if self.error then
      assert(false, self.error)
    end
    self.completed = false
    local newResult = self.result
    self.result = lastResult
    return newResult
  end
  setmetatable(await, await)
  coroutine.resume(f, await, ...)
end

return libs
