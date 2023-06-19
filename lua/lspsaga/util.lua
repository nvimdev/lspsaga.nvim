local api, lsp = vim.api, vim.lsp
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local M = {}
local saga_augroup = require('lspsaga').saga_augroup

M.iswin = uv.os_uname().sysname:match('Windows')
M.ismac = uv.os_uname().sysname == 'Darwin'

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

--get icon hlgroup color
function M.icon_from_devicon(ft)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if not ok then
    return ''
  end
  return devicons.get_icon_by_filetype(ft)
end

function M.tbl_index(tbl, val)
  for index, v in pairs(tbl) do
    if v == val then
      return index
    end
  end
end

function M.close_preview_autocmd(bufnr, winids, events, callback)
  api.nvim_create_autocmd(events, {
    group = saga_augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      local window = require('lspsaga.window')
      window.nvim_close_valid_window(winids)
      if callback then
        callback()
      end
    end,
  })
end

-- get client by methods
function M.get_client_by_method(methods)
  methods = type(methods) == 'string' and { methods } or methods
  local clients = lsp.get_active_clients({ bufnr = 0 })
  for _, client in ipairs(clients or {}) do
    local support = true
    for _, method in ipairs(methods) do
      if not client.supports_method(method) then
        support = false
        break
      end
    end

    if support then
      return client
    end
  end
end

local function feedkeys(key)
  local k = api.nvim_replace_termcodes(key, true, false, true)
  api.nvim_feedkeys(k, 'x', false)
end

function M.scroll_in_peek(bufnr, winid)
  local config = require('lspsaga').config
  if not api.nvim_win_is_valid(winid) then
    return
  end
  for i, map in ipairs({ config.scroll_preview.scroll_down, config.scroll_preview.scroll_up }) do
    api.nvim_buf_set_keymap(bufnr, 'n', map, '', {
      noremap = true,
      nowait = true,
      callback = function()
        if api.nvim_win_is_valid(winid) then
          api.nvim_win_call(winid, function()
            local key = i == 1 and '<C-d>' or '<C-u>'
            feedkeys(key)
          end)
          return
        end
        M.delete_scroll_map(bufnr)
      end,
    })
  end
end

function M.delete_scroll_map(bufnr)
  local config = require('lspsaga').config
  api.nvim_buf_del_keymap(bufnr, 'n', config.scroll_preview.scroll_down)
  api.nvim_buf_del_keymap(bufnr, 'n', config.scroll_preview.scroll_up)
end

function M.gen_truncate_line(width)
  local char = '─'
  return char:rep(math.floor(width / api.nvim_strwidth(char)))
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
  winid = type(winid) == 'table' and { winid } or winid
  for _, id in ipairs(winid) do
    if api.nvim_win_is_valid(id) then
      api.nvim_win_close(id, true)
    end
  end
end

return M
