local fn, health, api = vim.fn, vim.health, vim.api
local M = {}

local nvim_09 = vim.fn.has('nvim-0.9') == 1
local start = nvim_09 and health.start or health.report_start
local ok = nvim_09 and health.ok or health.report_ok
local error = nvim_09 and health.error or health.report_error
local warn = nvim_09 and health.warn or health.report_warn

local function treesitter_check()
  if fn.executable('tree-sitter') == 0 then
    warn('`tree-sitter` executable not found ')
  else
    ok('`tree-sitter` found ')
  end

  for _, parser in ipairs({ 'markdown', 'markdown_inline' }) do
    local installed = #api.nvim_get_runtime_file('parser/' .. parser .. '.so', false)
    if installed == 0 then
      error('tree-sitter `' .. parser .. '` parser not found')
    else
      ok('tree-sitter `' .. parser .. '` parser found')
    end
  end
end

M.check = function()
  start('Lspsaga.nvim report')
  treesitter_check()
end

return M
