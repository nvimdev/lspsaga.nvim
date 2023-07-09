local fn, uv = vim.fn, vim.version().minor >= 10 and vim.uv or vim.loop
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

local function tbl_to_string(tbl)
  return vim.json.encode(tbl)
end

function log:new(method, params, result)
  self.logfile = log_path()
  self.content = header()
    .. ' ['
    .. method
    .. '] [param] '
    .. tbl_to_string(params)
    .. ' [result] '
    .. tbl_to_string(result)
  return self
end

function log:write()
  local fd = uv.fs_open(self.logfile, 'w', 438)
  uv.fs_write(fd, self.content, function(err, bytes)
    if err then
      error('[Lspsaga] write to log failed')
    end
    if bytes == 0 then
      print('[Lspsaga] write to log file failed bytes: ' .. bytes)
    end
  end)
end

function log:open()
  vim.cmd.edit(log_path())
end

return log
