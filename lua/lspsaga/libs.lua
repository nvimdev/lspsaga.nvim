local api = vim.api
local is_windows = vim.loop.os_uname().sysname == "Windows"
local path_sep = is_windows and '\\' or '/'

-- check index in table
local function has_key (tab,idx)
  for index,_ in pairs(tab) do
    if index == idx then
      return true
    end
  end
  return false
end

local function nvim_create_augroup(group_name,definitions)
  vim.api.nvim_command('augroup '..group_name)
  vim.api.nvim_command('autocmd!')
  for _, def in ipairs(definitions) do
    local command = table.concat(vim.tbl_flatten{'autocmd', def}, ' ')
    vim.api.nvim_command(command)
  end
  vim.api.nvim_command('augroup END')
end

local function nvim_create_keymap(definitions,lhs)
  for _, def in pairs(definitions) do
    local bufnr = def[1]
    local mode = def[2]
    local key = def[3]
    local rhs = def[4]
    api.nvim_buf_set_keymap(bufnr,mode,key,rhs,lhs)
  end
end

local function check_lsp_active()
  local active_clients = vim.lsp.get_active_clients()
  if next(active_clients) == nil then
    return false,'[lspsaga] No lsp client available'
  end
  return true,nil
end

local function result_isempty(res)
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

return {
  is_windows = is_windows,
  path_sep = path_sep,
  has_key = has_key,
  nvim_create_augroup = nvim_create_augroup,
  nvim_create_keymap = nvim_create_keymap,
  check_lsp_active = check_lsp_active,
  result_isempty = result_isempty
}
