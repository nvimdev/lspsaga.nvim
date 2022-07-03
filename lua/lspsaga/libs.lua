local api = vim.api
local libs = {}
local server_filetype_map = require('lspsaga').config_values.server_filetype_map
local saga_augroup = require('lspsaga').saga_augroup

function libs.is_windows()
  return vim.loop.os_uname().sysname:find("Windows", 1, true) and true
end

local path_sep = libs.is_windows() and '\\' or '/'

function libs.get_home_dir()
  if libs.is_windows() then
    return os.getenv("USERPROFILE")
  end
  return os.getenv("HOME")
end

-- check index in table
function libs.has_key (tab,idx)
  for index,_ in pairs(tab) do
    if index == idx then
      return true
    end
  end
  return false
end

function libs.has_value(tbl,val)
  for _,v in pairs(tbl)do
    if v == val then
      return true
    end
  end
  return false
end

function libs.nvim_create_keymap(definitions,lhs)
  for _, def in pairs(definitions) do
    local bufnr = def[1]
    local mode = def[2]
    local key = def[3]
    local rhs = def[4]
    api.nvim_buf_set_keymap(bufnr,mode,key,rhs,lhs)
  end
end

function libs.check_lsp_active()
  local active_clients = vim.lsp.buf_get_clients()
  if next(active_clients) == nil then
    return false
  end
  return true
end

function libs.result_isempty(res)
  if res == nil then return true end
  if type(res) ~= "table" then
    vim.notify('[Lspsaga] Server return wrong response')
    return
  end
  for _,v in pairs(res) do
    if next(v) == nil then
      return true
    end
    if not v.result then
      return true
    end
    if next(v.result) == nil then
      return true
    end
  end
  return false
end

function libs.split_by_pathsep(text,start_pos)
  local pattern = libs.is_windows() and path_sep or '/'..path_sep
  local short_text = ''
  local split_table = {}
  for word in text:gmatch('[^'..pattern..']+') do
    table.insert(split_table,word)
  end

  for i = start_pos,#split_table,1 do
    short_text = short_text .. split_table[i]
    if i ~= #split_table then
      short_text = short_text .. path_sep
    end
  end
  return short_text
end

function libs.get_lsp_root_dir()
  if not libs.check_lsp_active() then
    return
  end

  local clients = vim.lsp.get_active_clients()
  for _,client in pairs(clients) do
    if (client.config.filetypes and client.config.root_dir) then
      if type(client.config.filetypes) == "table" then
        if libs.has_value(client.config.filetypes,vim.bo.filetype) then
          return client.config.root_dir
        end
      elseif type(client.config.filetypes) == "string" then
        if client.config.filetypes == vim.bo.filetype then
          return client.config.root_dir
        end
      end
    else
      for name,fts in pairs(server_filetype_map) do
        for _, ft in pairs(fts) do
          if (ft == vim.bo.filetype and client.config.name == name and client.config.root_dir) then
            return client.config.root_dir
          end
        end
      end
    end
  end
  return ''
end

function libs.apply_keys(ns)
  return function(func, keys)
    keys = type(keys) == "string" and {keys} or keys
    local fmt = "nnoremap <buffer><nowait><silent>%s <cmd>lua require('lspsaga.%s').%s()<CR>"

    vim.tbl_map(function(key)
      api.nvim_command(string.format(fmt, key, ns, func))
    end, keys)
  end
end

function libs.close_preview_autocmd(bufnr,winid,events)
  api.nvim_create_autocmd(events,{
    group = saga_augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      if api.nvim_win_is_valid(winid) then
        api.nvim_win_close(winid,true)
      end
    end
  })
end

function libs.disable_move_keys(bufnr)
  local keys = { 'h','ge','e','0','$','l','w','b','<Bs>'}
  local opts = { nowait = true,noremap = true,silent = true}
  for _,key in pairs(keys) do
    api.nvim_buf_set_keymap(bufnr,'n',key,'',opts)
  end
end

function libs.async(routine, ...)
	local f = coroutine.create(function(await, ...) routine(await, ...) end)
	local await = { error = nil, result = nil, completed = false }
	local complete = function(arg, err)
		await.result = arg
		await.error = err
		await.completed = true
		coroutine.resume(f)
	end
	await.resolve = function(arg) complete(arg, nil) end
	await.reject = function(err) complete(nil, err) end
	await.__call = function(self, wait, ...)
		local lastResult = self.result
		self.completed = false
		wait(self, ...)
		if not self.completed then coroutine.yield(f, ...) end
		if self.error then assert(false, self.error) end
		self.completed = false
		local newResult = self.result
		self.result = lastResult
		return newResult
	end
	setmetatable(await, await)
	coroutine.resume(f, await, ...)
end

return libs
