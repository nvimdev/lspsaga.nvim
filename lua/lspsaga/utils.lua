local M = {}

function M.as_table(value)
  return type(value) == 'string' and { value } or value
end

--- Creates a buffer local mapping.
---@param buffer number
---@param modes string|table<string>
---@param keys string|table<string>
---@param rhs string|function
---@param opts? table
function M.map_keys(buffer, modes, keys, rhs, opts)
  opts = opts or {}

  if type(rhs) == 'function' then
    opts.callback = rhs
    rhs = ''
  end

  for _, mode in ipairs(M.as_table(modes)) do
    for _, lhs in ipairs(M.as_table(keys)) do
      vim.api.nvim_buf_set_keymap(buffer, mode, lhs, rhs, opts)
    end
  end
end

return M
