local api, lsp = vim.api, vim.lsp
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local M = {}

M.iswin = uv.os_uname().sysname:match('Windows')
M.ismac = uv.os_uname().sysname == 'Darwin'
M.is_ten = vim.version().minor >= 10

M.path_sep = M.iswin and '\\' or '/'

function M.path_join(...)
  return table.concat({ ... }, M.path_sep)
end

function M.path_itera(buf)
  local parts = vim.split(api.nvim_buf_get_name(buf), M.path_sep, { trimempty = true })
  local index = #parts + 1
  return function()
    index = index - 1
    if index > 0 then
      return parts[index]
    end
  end
end

function M.path_sub(fname, root)
  local pwd = uv.cwd()
  if root and fname:sub(1, #root) == root then
    root = root
  elseif fname:sub(1, #pwd) == pwd then
    root = pwd
  else
    root = vim.env.HOME
  end
  root = root:sub(#root - #M.path_sep + 1) == M.path_sep and root or root .. M.path_sep
  return fname:gsub(vim.pesc(root), '')
end

--get icon hlgroup color
function M.icon_from_devicon(ft)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if not ok then
    return ''
  end
  return devicons.get_icon_by_filetype(ft)
end

---get index from a list-like table
function M.tbl_index(tbl, val)
  for index, v in ipairs(tbl) do
    if v == val then
      return index
    end
  end
end

-- get client by methods
function M.get_client_by_method(method)
  if vim.version().minor >= 10 then
    return lsp.get_clients({ bufnr = 0, method = method })
  end

  ---@diagnostic disable-next-line: deprecated
  local clients = lsp.get_active_clients({ bufnr = 0 })
  local supports = {}

  for _, client in ipairs(clients or {}) do
    if client.supports_method(method) then
      supports[#supports + 1] = client
    end
  end
  return supports
end

function M.feedkeys(key)
  local k = api.nvim_replace_termcodes(key, true, false, true)
  api.nvim_feedkeys(k, 'nx', false)
end

function M.scroll_in_float(bufnr, winid)
  local config = require('lspsaga').config
  if not api.nvim_win_is_valid(winid) or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  for i, map in ipairs({ config.scroll_preview.scroll_down, config.scroll_preview.scroll_up }) do
    M.map_keys(bufnr, map, function()
      if api.nvim_win_is_valid(winid) then
        api.nvim_win_call(winid, function()
          local key = i == 1 and '<C-d>' or '<C-u>'
          M.feedkeys(key)
        end)
      end
    end)
  end
end

function M.delete_scroll_map(bufnr)
  local config = require('lspsaga').config
  api.nvim_buf_del_keymap(bufnr, 'n', config.scroll_preview.scroll_down)
  api.nvim_buf_del_keymap(bufnr, 'n', config.scroll_preview.scroll_up)
end

function M.gen_truncate_line(width)
  return ('─'):rep(width)
end

function M.get_max_content_length(contents)
  vim.validate({
    contents = { contents, 't' },
  })
  local cells = {}
  for _, v in pairs(contents) do
    if v:find('\n.') then
      local tbl = vim.split(v, '\n')
      vim.tbl_map(function(s)
        table.insert(cells, #s)
      end, tbl)
    else
      table.insert(cells, #v)
    end
  end
  table.sort(cells)
  return cells[#cells]
end

function M.close_win(winid)
  for _, id in ipairs(M.as_table(winid)) do
    if api.nvim_win_is_valid(id) then
      api.nvim_win_close(id, true)
    end
  end
end

function M.get_max_float_width(percent)
  percent = percent or 0.6
  return math.floor(vim.o.columns * percent)
end

function M.win_height_increase(content, percent)
  local increase = 0
  local max_width = M.get_max_float_width(percent)
  local max_len = M.get_max_content_length(content)
  local new = {}
  for _, v in pairs(content) do
    if v:find('\n.') then
      vim.list_extend(new, vim.split(v, '\n'))
    else
      new[#new + 1] = v
    end
  end
  if max_len > max_width then
    vim.tbl_map(function(s)
      local cols = vim.fn.strdisplaywidth(s)
      if cols > max_width then
        increase = increase + math.floor(cols / max_width)
      end
    end, new)
  end
  return increase
end

function M.as_table(value)
  return type(value) ~= 'table' and { value } or value
end

--- Creates a buffer local mapping.
---@param buffer number
---@param keys string|table<string>
---@param rhs string|function
---@param modes string|table<string>|nil
---@param opts table|nil
function M.map_keys(buffer, keys, rhs, modes, opts)
  opts = opts or {}
  opts.nowait = true
  opts.noremap = true
  modes = modes or 'n'

  if type(rhs) == 'function' then
    opts.callback = rhs
    rhs = ''
  end

  for _, mode in ipairs(M.as_table(modes)) do
    for _, lhs in ipairs(M.as_table(keys)) do
      api.nvim_buf_set_keymap(buffer, mode, lhs, rhs, opts)
    end
  end
end

function M.res_isempty(results)
  -- handle {{}}
  if vim.tbl_isempty(results) then
    return true
  end
  for _, res in pairs(results) do
    if res.result and #res.result > 0 then
      return false
    end
  end
  return true
end

function M.nvim_ten()
  return vim.version().minor >= 10
end

---sub c/ cpp header file path when in macos
---@return string
function M.sub_mac_c_header(fname)
  local pos = fname:find('./usr/include')
  if not pos then
    return fname
  end
  return fname:sub(pos + 1)
end

function M.valid_markdown_parser()
  local parsers = { 'parser/markdown.so', 'parser/markdown_inline.so' }
  for _, p in ipairs(parsers) do
    if #api.nvim_get_runtime_file(p, true) == 0 then
      vim.notify_once('[Lspsaga] for better experience instal markdown relate tresitter parser')
      return
    end
  end
end

function M.get_bold_num()
  local line = api.nvim_get_current_line()
  local num = line:match('%*%*(%d+)%*%*')
  if num then
    num = tonumber(num)
  end
  return num
end

function M.sub_rust_toolchains(fname)
  local rustup_home = os.getenv('RUSTUP_HOME') or vim.fs.joinpath(vim.env.HOME, '.rustup')
  local toolchains = vim.fs.joinpath(rustup_home, 'toolchains')
  local parts = vim.split(fname, M.path_sep, { trimempty = true })
  local count = #vim.split(toolchains, M.path_sep, { trimempty = true })
  return vim.fs.joinpath(unpack(parts, count + 1))
end

return M
