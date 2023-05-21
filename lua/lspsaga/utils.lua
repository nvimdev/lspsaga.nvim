local M = {}

function M.get_as_table(value)
  return type(value) == 'string' and { value } or value
end

function M.map_keys(mode, keys, action, opts)
  for _, key in pairs(M.get_as_table(keys)) do
    vim.keymap.set(mode, key, action, opts)
  end
end

return M
