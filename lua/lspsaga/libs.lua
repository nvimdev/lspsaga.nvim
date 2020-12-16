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

return {
  is_windows = is_windows,
  path_sep = path_sep,
  has_key = has_key
}
