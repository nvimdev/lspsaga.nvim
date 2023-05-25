local fn, uv = vim.fn, vim.loop
local util = require('lspsaga.util')
local log = {}

local function log_path()
  local data_path = fn.stdpath('data')
  return util.path_join(data_path, 'lspsaga.log')
end

local function header()
  local time = os.date('%m-%d-%H:%M:%S')
  return '[Lspsaga] [' .. time .. ']'
end

local function fmt(method, result)
  local data = vim.json.encode(result)
  return header() .. ' [' .. method .. '] ' .. data
end

function log:new(method, result)
  self.content = fmt(method, result)
  self.logfile = log_path()
  return self
end

function log:write()
  local fd = assert(uv.fs_open(self.logfile, 'w', 438))
  uv.fs_write(fd, self.content, function(err, result)
    if err then
      error('[Lspsaga] write to log failed')
    end
    print(result)
  end)
end

function log:open()
  vim.cmd.edit(log_path())
end

return log
