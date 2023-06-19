local api, lsp = vim.api, vim.lsp
local saga_conf = require('lspsaga').config
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

function M.has_value(filetypes, val)
  if type(filetypes) == 'table' then
    for _, v in pairs(filetypes) do
      if v == val then
        return true
      end
    end
  elseif type(filetypes) == 'string' then
    if filetypes == val then
      return true
    end
  end
  return false
end

function M.merge_table(t1, t2)
  for _, v in pairs(t2) do
    table.insert(t1, v)
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

function M.find_buffer_by_filetype(ft)
  local all_bufs = vim.fn.getbufinfo()
  local filetype = ''
  for _, bufinfo in pairs(all_bufs) do
    filetype = api.nvim_buf_get_option(bufinfo['bufnr'], 'filetype')

    if type(ft) == 'table' and M.has_value(ft, filetype) then
      return true, bufinfo['bufnr']
    end

    if filetype == ft then
      return true, bufinfo['bufnr']
    end
  end

  return false, nil
end

function M.add_client_filetypes(client, fts)
  if not client.config.filetypes then
    client.config.filetypes = fts
  end
end

-- get client by capabilities
function M.get_client_by_cap(caps)
  local client_caps = {
    ['string'] = function(instance)
      M.add_client_filetypes(instance, { vim.bo.filetype })
      if
        instance.server_capabilities[caps]
        and M.has_value(instance.config.filetypes, vim.bo.filetype)
      then
        return instance
      end
      return nil
    end,
    ['table'] = function(instance)
      M.add_client_filetypes(instance, { vim.bo.filetype })
      if
        vim.tbl_get(instance.server_capabilities, unpack(caps))
        and M.has_value(instance.config.filetypes, vim.bo.filetype)
      then
        return instance
      end
      return nil
    end,
  }

  local clients = lsp.get_active_clients({ bufnr = 0 })
  local client
  for _, instance in pairs(clients) do
    client = client_caps[type(caps)](instance)
    if client ~= nil then
      break
    end
  end
  return client
end

local function feedkeys(key)
  local k = api.nvim_replace_termcodes(key, true, false, true)
  api.nvim_feedkeys(k, 'x', false)
end

function M.scroll_in_preview(bufnr, preview_winid)
  local config = require('lspsaga').config
  if preview_winid and api.nvim_win_is_valid(preview_winid) then
    for i, map in ipairs({ config.scroll_preview.scroll_down, config.scroll_preview.scroll_up }) do
      api.nvim_buf_set_keymap(bufnr, 'n', map, '', {
        noremap = true,
        nowait = true,
        callback = function()
          if api.nvim_win_is_valid(preview_winid) then
            api.nvim_win_call(preview_winid, function()
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
end

function M.delete_scroll_map(bufnr)
  local config = require('lspsaga').config
  pcall(api.nvim_buf_del_keymap, bufnr, 'n', config.scroll_preview.scroll_down)
  pcall(api.nvim_buf_del_keymap, bufnr, 'n', config.scroll_preview.scroll_up)
end

function M.jump_beacon(bufpos, width)
  if not saga_conf.beacon.enable then
    return
  end

  if width == 0 or not width then
    return
  end

  local opts = {
    relative = 'win',
    bufpos = bufpos,
    height = 1,
    width = width,
    row = 0,
    col = 0,
    anchor = 'NW',
    focusable = false,
    no_size_override = true,
    noautocmd = true,
  }

  local window = require('lspsaga.window')
  local _, winid = window.create_win_with_border({
    contents = { '' },
    noborder = true,
    winblend = 0,
    highlight = {
      normal = 'SagaBeacon',
    },
  }, opts)

  local timer = vim.loop.new_timer()
  timer:start(
    0,
    60,
    vim.schedule_wrap(function()
      if not api.nvim_win_is_valid(winid) then
        return
      end
      local blend = vim.wo[winid].winblend + saga_conf.beacon.frequency
      if blend > 100 then
        blend = 100
      end
      vim.wo[winid].winblend = blend
      if vim.wo[winid].winblend == 100 and not timer:is_closing() then
        timer:stop()
        timer:close()
        api.nvim_win_close(winid, true)
      end
    end)
  )
end

function M.gen_truncate_line(width)
  local char = '─'
  return char:rep(math.floor(width / api.nvim_strwidth(char)))
end

function M.server_ready(buf, callback)
  local timer = vim.loop.new_timer()
  timer:start(100, 10, function()
    local clients = vim.lsp.get_active_clients({ bufnr = buf })
    local ready = true
    for _, client in ipairs(clients) do
      if next(client.messages.progress) ~= nil then
        ready = false
      end
    end
    if ready and not timer:is_closing() then
      timer:stop()
      timer:close()
      callback()
    end
  end)
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

return M
