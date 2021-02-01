local api = vim.api
local is_windows = vim.loop.os_uname().sysname == "Windows"
local path_sep = is_windows and '\\' or '/'
local libs = {}

function libs.get_home_dir()
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

function libs.nvim_create_augroup(group_name,definitions)
  vim.api.nvim_command('augroup '..group_name)
  vim.api.nvim_command('autocmd!')
  for _, def in ipairs(definitions) do
    local command = table.concat(vim.tbl_flatten{'autocmd', def}, ' ')
    vim.api.nvim_command(command)
  end
  vim.api.nvim_command('augroup END')
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
  local active_clients = vim.lsp.get_active_clients()
  if next(active_clients) == nil then
    return false,'[lspsaga] No lsp client available'
  end
  return true,nil
end

function libs.result_isempty(res)
  if type(res) ~= "table" then
    assert(type(res) == 'table', string.format("Expected table, got %s", type(res)))
    return
  end
  for _,v in ipairs(res) do
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
  local pattern = is_windows and path_sep or '/'..path_sep
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
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  local clients = vim.lsp.get_active_clients()
  for _,client in pairs(clients) do
    if client.config.root_dir then
      if libs.has_value(client.config.filetypes,vim.bo.filetype) then
        return client.config.root_dir
      end
    end
  end
  return ''
end

return libs
