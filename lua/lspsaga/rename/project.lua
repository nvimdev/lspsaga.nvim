local lsp, fn, api = vim.lsp, vim.fn, vim.api
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local config = require('lspsaga').config
local win = require('lspsaga.window')
local ns = api.nvim_create_namespace('SagaProjectRename')
local util = require('lspsaga.util')
--project rename module
local M = {}

local function safe_close(handle)
  if not uv.is_closing(handle) then
    uv.close(handle)
  end
end

local function get_root_dir()
  ---@diagnostic disable-next-line: deprecated
  local get_clients = vim.version().minor >= 10 and lsp.get_clients or lsp.get_active_clients
  local clients = get_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.config.root_dir then
      return client.config.root_dir
    end
  end
end

local function decode(data)
  local t = vim.split(data, '\n', { trimempty = true })
  local result = {}
  for _, v in pairs(t) do
    local tbl = vim.json.decode(v)
    if tbl.type == 'match' then
      local path = tbl.data.path.text
      if not result[path] then
        result[path] = {}
      end
      result[path][#result[path] + 1] = tbl
    end
  end
  return result
end

local function create_win()
  local win_height = api.nvim_win_get_height(0)
  local win_width = api.nvim_win_get_width(0)
  local float_opt = {
    height = math.floor(win_height * config.rename.project_max_height),
    width = math.floor(win_width * config.rename.project_max_width),
    title = config.ui.title and 'Project' or nil,
  }

  return win
    :new_float(float_opt, true)
    :bufopt({
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :winhl('SagaNormal', 'SagaBorder')
    :wininfo()
end

local function find_data_by_lnum(data, lnum)
  for _, item in pairs(data) do
    for _, v in ipairs(item) do
      if v.winline == lnum then
        return v
      end
    end
  end
end

local function apply_map(bufnr, winid, data, new_name)
  util.map_keys(bufnr, config.rename.keys.select, function()
    local curlnum = api.nvim_win_get_cursor(winid)[1]
    if fn.indent(curlnum) ~= 2 then
      return
    end
    local item = find_data_by_lnum(data, curlnum)

    if not item.selected then
      item.selected = true
      api.nvim_buf_add_highlight(bufnr, ns, 'SagaSelect', curlnum - 1, 0, -1)
      return
    end
    item.selected = false
    api.nvim_buf_clear_namespace(bufnr, ns, curlnum - 1, curlnum)
    api.nvim_buf_add_highlight(bufnr, ns, 'Comment', curlnum - 1, 0, -1)
  end)

  util.map_keys(bufnr, config.rename.keys.quit, function()
    api.nvim_win_close(winid, true)
  end)

  util.map_keys(bufnr, config.rename.keys.exec, function()
    for fname, v in pairs(data) do
      for _, item in ipairs(v) do
        if item.selected then
          local buf = fn.bufadd(fname)
          if not api.nvim_buf_is_loaded(buf) then
            fn.bufload(buf)
          end
          for _, match in ipairs(item.data.submatches) do
            api.nvim_buf_set_text(
              buf,
              item.data.line_number - 1,
              match.start,
              item.data.line_number - 1,
              match['end'],
              { new_name }
            )
            api.nvim_buf_call(buf, function()
              vim.cmd.write()
            end)
          end
        end
      end
    end
    api.nvim_win_close(winid, true)
  end)
end

local function render(chunks, new_name)
  local result = decode(chunks)
  local line = 1
  if vim.tbl_isempty(result) then
    return
  end
  local bufnr, winid = create_win()

  for fname, item in pairs(result) do
    fname = util.path_sub(fname, get_root_dir())
    api.nvim_buf_set_lines(bufnr, line - 1, line - 1, false, { fname })
    api.nvim_buf_add_highlight(bufnr, ns, 'SagaFinderFname', line - 1, 0, -1)
    line = line + 1
    vim.tbl_map(function(val)
      local ln = val.data.line_number
      local text = 'ln:' .. ln .. (' '):rep(5 - #tostring(ln)) .. vim.trim(val.data.lines.text)
      api.nvim_buf_set_lines(bufnr, line - 1, -1, false, { (' '):rep(2) .. text })
      api.nvim_buf_add_highlight(bufnr, ns, 'Comment', line - 1, 0, -1)
      val.winline = line
      line = line + 1
    end, item)
  end
  api.nvim_win_set_cursor(winid, { 2, 10 })
  apply_map(bufnr, winid, result, new_name)
end

function M:new(args)
  if fn.executable('rg') == 0 then
    vim.notify('[lspsaga] failed finding rg')
    return
  end

  if #args < 2 then
    vim.notify('[lspsaga] missing search pattern or new name')
    return
  end

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdin = uv.new_pipe(false)

  local handle
  local chunks = {}
  local root_dir = get_root_dir()
  if not root_dir then
    vim.notify('[lspsaga] buffer run in single file mode')
    return
  end

  handle, _ = uv.spawn('rg', {
    args = { args[1], root_dir, '--json', unpack(args[3]) },
    stdio = { stdin, stdout, stderr },
  }, function(_, _)
    uv.read_stop(stdout)
    uv.read_stop(stderr)
    safe_close(handle)
    safe_close(stdout)
    safe_close(stderr)
    -- parse after close
    vim.schedule(function()
      render(table.concat(chunks), args[2])
    end)
  end)

  uv.read_start(stdout, function(err, data)
    assert(not err, err)

    if data then
      chunks[#chunks + 1] = data
    end
  end)
end

return M
