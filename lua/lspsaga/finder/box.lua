local M = {}
local api = vim.api

function M.get_methods(args)
  local methods = {
    ['def'] = 'textDocument/definition',
    ['ref'] = 'textDocument/references',
    ['imp'] = 'textDocument/implementation',
  }
  local keys = vim.tbl_keys(methods)
  return vim.tbl_map(function(item)
    if vim.tbl_contains(keys, item) then
      return methods[item]
    end
  end, args)
end

function M.parse_argument(args)
  local methods, layout
  for _, arg in ipairs(args) do
    if arg:find('%w+%+%w+') then
      methods = vim.split(arg, '+', { plain = true })
    end
    if arg:find('%+%+') then
      layout = vim.split(arg, '%+%+')[1]
    end
  end
  return methods, layout
end

return M
