local config = require('lspsaga').config
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymap
local def = {}

-- a double linked list for store the node infor
local ctx = {}

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

---Get current node by id
---@private
---@return table|nil
local function find_node(winid)
  if vim.tbl_isempty(ctx) then
    return nil
  end
  local key = vim.tbl_keys(ctx)[1]
  local node = ctx[key].node
  while true do
    if node.winid == winid then
      break
    end
    node = node.next
  end
  return node
end

---remove a node
---@private
local function remove(node)
  local cur_node = find_node(node.winid)
  if not cur_node then
    return false
  end
  local prev = cur_node.prev
  local next = cur_node.next
  if prev then
    if next then
      next.prev = prev
    end
    prev.next = next
  end
  cur_node = nil
  local key = vim.tbl_keys(ctx)[1]
  ctx[key].length = ctx[key].length - 1
  return true
end

---find the last node
---@private
---@return table
local function last_node(list)
  local node = list.node
  while true do
    if not node.next then
      break
    end
    node = node.next
  end
  return node
end

---push a node into the ctx
---@private
local function push(node)
  if vim.tbl_isempty(ctx) then
    ctx[node.main_winid] = {
      length = 1,
      node = node,
    }
    return
  end
  local key = vim.tbl_keys(ctx)[1]
  local tail = last_node(ctx[key])
  tail.next = node
  node.prev = tail
  ctx[key].length = ctx[key].length + 1
end

function def:title_text(opts, link)
  local libs = require('lspsaga.libs')
  link = vim.split(link, libs.path_sep, { trimempty = true })
  if #link > 2 then
    link = table.concat(link, libs.path_sep, #link - 1, #link)
  end
  local theme = require('lspsaga').theme()
  opts.title = {
    { theme.left, 'TitleSymbol' },
    { link, 'TitleString' },
    { theme.right, 'TitleSymbol' },
  }
  local data = libs.icon_from_devicon(vim.bo.filetype, true)
  if data then
    table.insert(opts.title, 2, { data[1] .. ' ', 'TitleFileIcon' })
    api.nvim_set_hl(0, 'TitleFileIcon', {
      background = config.ui.title,
      foreground = data[2],
    })
  end
end

local function get_uri_data(result)
  local uri, range

  if type(result[1]) == 'table' then
    uri = result[1].uri or result[1].targetUri
    range = result[1].range or result[1].targetRange
  else
    uri = result.uri or result.targetUri
    range = result.range or result.targetRange
  end

  if not uri then
    vim.notify('[Lspsaga] Does not find target uri', vim.log.levels.WARN)
    return
  end

  local bufnr = vim.uri_to_bufnr(uri)
  local link = vim.uri_to_fname(uri)

  if not api.nvim_buf_is_loaded(bufnr) then
    fn.bufload(bufnr)
  end

  local start_line = range.start.line
  local start_char_pos = range.start.character
  local end_char_pos = range['end'].character

  return bufnr, link, start_line, start_char_pos, end_char_pos
end

local in_process = 0
function def:peek_definition()
  local cur_winid = api.nvim_get_current_win()
  if in_process == cur_winid then
    vim.notify('[Lspsaga] Already have a peek_definition request please wait', vim.log.levels.WARN)
    return
  end
  in_process = cur_winid
  local current_buf = api.nvim_get_current_buf()
  -- { prev, next,main_winid,fname, winid, bufnr}
  local node = {}
  node.main_bufnr = current_buf
  node.main_winid = cur_winid
  node.fname = api.nvim_buf_get_name(current_buf)

  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  local current_word = fn.expand('<cword>')
  local from = { current_buf, pos[1], pos[2] + 1, 0 }
  local items = { { tagname = current_word, from = from } }
  fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

  local params = lsp.util.make_position_params()

  lsp.buf_request_all(current_buf, 'textDocument/definition', params, function(results)
    in_process = 0
    if not results or next(results) == nil then
      vim.notify(
        '[Lspsaga] response of request method textDocument/definition is nil',
        vim.log.levels.WARN
      )
      return
    end

    local result
    for _, res in pairs(results) do
      if res and res.result then
        result = res.result
      end
    end

    if not result then
      vim.notify(
        '[Lspsaga] response of request method textDocument/definition is nil',
        vim.log.levels.WARN
      )
      return
    end

    local bufnr, link, start_line, start_char_pos, end_char_pos = get_uri_data(result)
    node.link = link

    local opts = {
      relative = 'cursor',
      style = 'minimal',
    }
    local max_width = math.floor(vim.o.columns * 0.6)
    local max_height = math.floor(vim.o.lines * 0.6)

    opts.width = max_width
    opts.height = max_height

    opts = lsp.util.make_floating_popup_options(max_width, max_height, opts)

    opts.row = opts.row + 1
    local content_opts = {
      contents = {},
      filetype = vim.bo[current_buf].filetype,
      enter = true,
      highlight = {
        border = 'DefinitionBorder',
        normal = 'DefinitionNormal',
      },
    }
    --@deprecated when 0.9 release
    if fn.has('nvim-0.9') == 1 then
      self:title_text(opts, link)
    end

    local window = require('lspsaga.window')
    _, node.winid = window.create_win_with_border(content_opts, opts)
    vim.opt_local.modifiable = true
    api.nvim_win_set_var(node.winid, 'disable_winbar', true)
    api.nvim_win_set_buf(node.winid, bufnr)
    node.bufnr = bufnr
    api.nvim_buf_set_option(node.bufnr, 'bufhidden', 'wipe')
    --set the initail cursor pos
    api.nvim_win_set_cursor(node.winid, { start_line + 1, start_char_pos })
    vim.cmd('normal! zt')

    node.def_win_ns = api.nvim_create_namespace('DefinitionWinNs-' .. node.bufnr)
    api.nvim_buf_add_highlight(
      bufnr,
      node.def_win_ns,
      'DefinitionSearch',
      start_line,
      start_char_pos,
      end_char_pos
    )

    if vim.bo[bufnr].buflisted then
      api.nvim_win_set_hl_ns(node.winid, node.def_win_ns)
      api.nvim_set_hl(node.def_win_ns, 'Normal', {
        background = config.ui.normal,
      })
      api.nvim_set_hl(node.def_win_ns, 'SignColumn', {
        background = config.ui.normal,
      })
      api.nvim_set_hl(node.def_win_ns, 'DefinitionBorder', {
        background = config.ui.normal,
      })
    end

    self:apply_aciton_keys(bufnr, { start_line, start_char_pos })
    self:event(bufnr)
    push(node)
  end)
end

function def:event(bufnr)
  api.nvim_create_autocmd('QuitPre', {
    buffer = bufnr,
    once = true,
    callback = function(opt)
      local winid = fn.bufwinid(opt.buf)
      local node = find_node(winid)
      if not node then
        return
      end
      pcall(api.nvim_buf_clear_namespace, bufnr, node.def_win_ns, 0, -1)
    end,
  })
  api.nvim_create_autocmd('WinClosed', {
    buffer = bufnr,
    callback = function(opt)
      local wins = fn.win_findbuf(opt.buf)
      if #wins == 0 then
        return
      end
      if #wins == 2 then
        for _, map in pairs(config.definition.keys) do
          pcall(api.nvim_buf_del_keymap, opt.buf, 'n', map)
        end
      end
      local key = vim.tbl_keys(ctx)[1]
      if ctx[key].length == 1 then
        api.nvim_del_autocmd(opt.id)
      end
    end,
  })
end

local function unpack_maps()
  local maps = config.definition.keys
  local res = {}
  for key, val in pairs(maps) do
    if key ~= 'quit' or 'close' then
      res[key] = val
    end
  end
  return res
end

function def:apply_aciton_keys(bufnr, pos)
  local maps = unpack_maps()
  local opt = { buffer = true, nowait = true }

  local node_with_close = function()
    local winid = api.nvim_get_current_win()
    local node = find_node(winid)
    if not node then
      return
    end
    api.nvim_buf_clear_namespace(bufnr, node.def_win_ns, 0, -1)
    self:close_window(node.winid)
    return node
  end
  for action, key in pairs(maps) do
    keymap.set('n', key, function()
      local node = node_with_close()
      if not node then
        return
      end
      vim.cmd(action .. ' ' .. node.link)
      api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
      clean_ctx()
    end, opt)
  end

  keymap.set('n', config.definition.keys.quit, function()
    local node = node_with_close()
    if not node then
      return
    end
    if node.prev and api.nvim_win_is_valid(node.prev.winid) then
      api.nvim_set_current_win(node.prev.winid)
      remove(node)
    else
      clean_ctx()
    end
  end, opt)

  keymap.set('n', config.definition.keys.close, function()
    if vim.tbl_isempty(ctx) then
      return
    end
    local key = vim.tbl_keys(ctx)[1]
    local node = ctx[key].node
    while true do
      if node.winid and api.nvim_win_is_valid(node.winid) then
        api.nvim_win_close(node.winid, true)
        remove(node)
      end
      node = node.next
      if not node then
        break
      end
    end
    clean_ctx()
  end, opt)
end

function def:close_window(winid)
  if api.nvim_win_is_valid(winid) then
    api.nvim_win_close(winid, true)
  end
end

-- override the default the defintion handler
function def:goto_defintion()
  lsp.handlers['textDocument/definition'] = function(_, result, _, _)
    if not result or vim.tbl_isempty(result) then
      return
    end
    local _, link, start_line, start_char_pos, _ = get_uri_data(result)
    api.nvim_command('edit ' .. link)
    api.nvim_win_set_cursor(0, { start_line + 1, start_char_pos })
  end
  lsp.buf.definition()
end

def = setmetatable(def, {
  __newindex = function(_, k, v)
    ctx[k] = v
  end,
  __index = function(_, k, _)
    return ctx[k]
  end,
})

return def
