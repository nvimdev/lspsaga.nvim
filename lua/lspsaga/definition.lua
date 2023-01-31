local config = require('lspsaga').config
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymap
local libs = require('lspsaga.libs')
local window = require('lspsaga.window')
local def = {}

-- a double linked list for store the node infor
local ctx = {}

local function clean_ctx()
  ctx = {}
end

local function find_node(winid)
  for index, node in pairs(ctx.data or {}) do
    if node.winid == winid then
      return index
    end
  end
end

local function remove(index)
  table.remove(ctx.data, index)
  if #ctx.data == 0 then
    clean_ctx()
  end
end

local function push(node)
  if not ctx.data then
    ctx.data = {}
  end
  ctx.data[#ctx.data + 1] = node
end

local function stack_cap()
  if not ctx.data then
    return 0
  end
  return #ctx.data
end

function def:title_text(opts, link)
  if not link then
    return
  end
  link = vim.split(link, libs.path_sep, { trimempty = true })
  if #link > 2 then
    link = table.concat(link, libs.path_sep, #link - 1, #link)
  end
  opts.title = {
    { link, 'TitleString' },
  }
  local data = libs.icon_from_devicon(vim.bo.filetype)
  if data[1] then
    table.insert(opts.title, 1, { data[1] .. ' ', data[2] })
  end
end

local function get_uri_data(result)
  local uri, range

  if type(result[1]) == 'table' then
    uri = result[1].uri or result[1].targetUri
    range = result[1].range or result[1].targetSelectionRange
  else
    uri = result.uri or result.targetUri
    range = result.range or result.targetSelectionRange
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

  return bufnr, link, start_line, start_char_pos
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

    local bufnr, link, start_line, start_char_pos = get_uri_data(result)
    if not bufnr then
      return
    end

    node.link = link
    local opts = {}
    if stack_cap() == 0 then
      local cur_winline = fn.winline()
      local max_height = math.floor(vim.o.lines * 0.5)
      local max_width = math.floor(vim.o.columns * 0.6)
      opts = {
        relative = 'cursor',
        style = 'minimal',
        no_override_size = true,
        height = max_height,
        width = max_width,
      }
      if vim.o.lines - opts.height - cur_winline < 0 then
        vim.cmd('normal! zz')
        local keycode = api.nvim_replace_termcodes('5<C-e>', true, false, true)
        api.nvim_feedkeys(keycode, 'x', false)
      end
    else
      opts = api.nvim_win_get_config(cur_winid)
    end

    local content_opts = {
      contents = {},
      enter = true,
      bufnr = bufnr,
      highlight = {
        border = 'DefinitionBorder',
        normal = 'DefinitionNormal',
      },
    }
    --@deprecated when 0.9 release
    if fn.has('nvim-0.9') == 1 and config.ui.title then
      self:title_text(opts, link)
    end

    node.prev = api.nvim_get_current_win()
    _, node.winid = window.create_win_with_border(content_opts, opts)
    if config.symbol_in_winbar.enable then
      api.nvim_win_set_var(node.winid, 'disable_winbar', true)
    end
    vim.opt_local.modifiable = true
    node.bufnr = bufnr
    --set the initail cursor pos
    api.nvim_win_set_cursor(node.winid, { start_line + 1, start_char_pos })
    vim.cmd('normal! zt')

    self:apply_aciton_keys({ start_line, start_char_pos })
    self:event(bufnr)
    push(node)
  end)
end

function def:event(bufnr)
  api.nvim_create_autocmd('QuitPre', {
    once = true,
    callback = function()
      local curwin = vim.api.nvim_get_current_win()
      local node = find_node(curwin)
      if not node then
        return
      end
      remove(node)
    end,
  })
end

local function unpack_maps()
  local maps = config.definition
  local res = {}
  for key, val in pairs(maps) do
    if key ~= 'quit' or 'close' then
      res[key] = val
    end
  end
  return res
end

function def:apply_aciton_keys(pos)
  local maps = unpack_maps()
  local opt = { buffer = true, nowait = true }

  for action, key in pairs(maps) do
    keymap.set('n', key, function()
      local curwin = api.nvim_get_current_win()
      local index = find_node(curwin)
      if not index then
        return
      end

      api.nvim_win_close(curwin, true)
      local node = ctx.data[index]
      vim.cmd(action .. ' ' .. node.link)
      api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
      local width = #api.nvim_get_current_line()
      libs.jump_beacon({ pos[1], pos[2] }, width)
      clean_ctx()
    end, opt)
  end

  keymap.set('n', config.definition.quit, function()
    local curwin = api.nvim_get_current_win()
    local index = find_node(curwin)
    if not index then
      return
    end

    local node = ctx.data[index]
    if api.nvim_win_is_valid(node.prev) then
      api.nvim_set_current_win(node.prev)
    end
    self:close_window(node.winid)
    remove(index)
  end, opt)

  keymap.set('n', config.definition.close, function()
    if vim.tbl_isempty(ctx) then
      return
    end
    for _, item in pairs(ctx.data or {}) do
      if item.winid and api.nvim_win_is_valid(item.winid) then
        api.nvim_win_close(item.winid, true)
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
function def:goto_definition()
  lsp.handlers['textDocument/definition'] = function(_, result, _, _)
    if not result or vim.tbl_isempty(result) then
      return
    end
    local _, link, start_line, start_char_pos, _ = get_uri_data(result)
    api.nvim_command('edit ' .. link)
    api.nvim_win_set_cursor(0, { start_line + 1, start_char_pos })
    local width = #api.nvim_get_current_line()
    libs.jump_beacon({ start_line, start_char_pos }, width)
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
