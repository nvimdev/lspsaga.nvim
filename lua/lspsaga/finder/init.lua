local ly = require('lspsaga.layout')
local util = require('lspsaga.util')
local fd = {}
local ctx = {}

fd.__index = fd
fd.__newindex = function(t, k, v)
  rawset(t, k, v)
end

local function clean_ctx() end

local function get_methods(args)
  local methods = {
    ['def'] = 'textDoucment/definition',
    ['ref'] = 'textDocument/reference',
    ['imp'] = 'textDocument/implementation',
  }
  local keys = vim.tbl_keys(methods)
  return vim.tbl_map(function(item)
    if vim.tbl_contains(keys, item) then
      return methods[item]
    end
  end, args)
end

function fd:new(args)
  local methods = get_methods(args)
  local clients = util.get_client_by_method(methods)
end

return setmetatable(ctx, fd)
