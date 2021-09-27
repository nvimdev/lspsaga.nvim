local api = vim.api
local libs = {}
local server_filetype_map = require("lspsaga").config_values.server_filetype_map

function libs.is_windows()
  return vim.loop.os_uname().sysname:find("Windows", 1, true) and true
end

local path_sep = libs.is_windows() and "\\" or "/"

function libs.get_home_dir()
  if libs.is_windows() then
    return os.getenv "USERPROFILE"
  end
  return os.getenv "HOME"
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

function libs.has_value(tbl, val)
  for _, v in pairs(tbl) do
    if v == val then
      return true
    end
  end
  return false
end

function libs.nvim_create_augroup(group_name, definitions)
  vim.api.nvim_command("augroup " .. group_name)
  vim.api.nvim_command "autocmd!"
  for _, def in ipairs(definitions) do
    local command = table.concat(vim.tbl_flatten { "autocmd", def }, " ")
    vim.api.nvim_command(command)
  end
  vim.api.nvim_command "augroup END"
end

function libs.nvim_create_keymap(definitions, lhs)
  for _, def in pairs(definitions) do
    local bufnr = def[1]
    local mode = def[2]
    local key = def[3]
    local rhs = def[4]
    api.nvim_buf_set_keymap(bufnr, mode, key, rhs, lhs)
  end
end

function libs.check_lsp_active()
  local active_clients = vim.lsp.get_active_clients()
  if next(active_clients) == nil then
    return false, "[lspsaga] No lsp client available"
  end
  return true, nil
end

function libs.result_isempty(res)
  if type(res) ~= "table" then
    print "[Lspsaga] Server return wrong response"
    return
  end
  for _, v in pairs(res) do
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

function libs.split_by_pathsep(text, start_pos)
  local pattern = libs.is_windows() and path_sep or "/" .. path_sep
  local short_text = ""
  local split_table = {}
  for word in text:gmatch("[^" .. pattern .. "]+") do
    table.insert(split_table, word)
  end

  for i = start_pos, #split_table, 1 do
    short_text = short_text .. split_table[i]
    if i ~= #split_table then
      short_text = short_text .. path_sep
    end
  end
  return short_text
end

function libs.get_lsp_root_dir()
  local active, msg = libs.check_lsp_active()
  if not active then
    print(msg)
    return
  end
  local clients = vim.lsp.get_active_clients()
  for _, client in pairs(clients) do
    if client.config.filetypes and client.config.root_dir then
      if type(client.config.filetypes) == "table" then
        if libs.has_value(client.config.filetypes, vim.bo.filetype) then
          return client.config.root_dir
        end
      elseif type(client.config.filetypes) == "string" then
        if client.config.filetypes == vim.bo.filetype then
          return client.config.root_dir
        end
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
  return ""
end

function libs.apply_keys(ns)
  return function(func, keys)
    keys = type(keys) == "string" and { keys } or keys
    local fmt = "nnoremap <buffer><nowait><silent>%s <cmd>lua require('lspsaga.%s').%s()<CR>"

    vim.tbl_map(function(key)
      api.nvim_command(string.format(fmt, key, ns, func))
    end, keys)
  end
end

return libs
