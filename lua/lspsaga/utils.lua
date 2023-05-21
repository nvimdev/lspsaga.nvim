local M = {}

function M.as_table(value)
  return type(value) == 'string' and { value } or value
end

--- Creates a buffer local mapping.
---@param buffer number
---@param modes string|table<string>
---@param keys string|table<string>
---@param action string|function
---@param opts? table
function M.map_keys(buffer, modes, keys, action, opts)
  opts = opts or {}

  if type(action) == 'function' then
    opts.callback = action
    action = ''
  end

  for _, mode in pairs(M.as_table(modes)) do
    for _, key in pairs(M.as_table(keys)) do
      vim.api.nvim_buf_set_keymap(buffer, mode, key, action, opts)
    end
  end
end

return M
