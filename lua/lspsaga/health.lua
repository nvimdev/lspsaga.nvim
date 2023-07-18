local fn, health, api = vim.fn, vim.health, vim.api
local M = {}

local function treesitter_check()
  if fn.executable('tree-sitter') == 0 then
    health.warn('`tree-sitter` executable not found ')
  else
    health.ok('`tree-sitter` found ')
  end

  for _, parser in ipairs({ 'markdown', 'markdown_inline' }) do
    local installed = #api.nvim_get_runtime_file('parser/' .. parser .. '.so', false)
    if installed == 0 then
      health.error('tree-sitter `' .. parser .. '` parser not found')
    else
      health.ok('tree-sitter `' .. parser .. '` parser found')
    end
  end
end

M.check = function()
  health.start('Lspsaga.nvim report')
  treesitter_check()
end

return M
