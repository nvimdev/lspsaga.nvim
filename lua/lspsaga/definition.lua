local config = require('lspsaga').config
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymap
local libs = require('lspsaga.libs')
local window = require('lspsaga.window')
local group = api.nvim_create_augroup('peek_definition', { clear = true })
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
    pcall(api.nvim_clear_autocmds, { event = 'WinClosed', group = group })
    ctx.main_winid = nil
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
  local res = {}

  if type(result[1]) == 'table' then
    res.uri = result[1].uri or result[1].targetUri
    res.range = result[1].range or result[1].targetSelectionRange
  else
    res.uri = result.uri or result.targetUri
    res.range = result.range or result.targetSelectionRange
  end

  if not res.uri then
    vim.notify('[Lspsaga] Does not find target uri', vim.log.levels.WARN)
    return
  end

  res.bufnr = vim.uri_to_bufnr(res.uri)

  if not api.nvim_buf_is_loaded(res.bufnr) then
    fn.bufload(res.bufnr)
    res.wipe = true
  end

  return res
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

local function apply_aciton_keys(pos)
  local maps = unpack_maps()
  local opt = { buffer = true, nowait = true }

  for action, key in pairs(maps) do
    keymap.set('n', key, function()
      local curwin = api.nvim_get_current_win()
      local index = find_node(curwin)
      if not index then
        return
      end

      local link = ctx.data[index].link
      local curbuf = api.nvim_get_current_buf()
      if #fn.win_findbuf(curbuf) == 1 then
        api.nvim_set_option_value('bufhidden', 'wipe', { buf = curbuf })
      end

      api.nvim_win_close(curwin, true)
      vim.cmd(action .. ' ' .. link)
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
    api.nvim_win_close(curwin, true)
    if api.nvim_win_is_valid(node.prev) then
      api.nvim_set_current_win(node.prev)
    end
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

    local res = get_uri_data(result)
    if not res or not res.bufnr then
      return
    end

    node.link = vim.uri_to_fname(res.uri)
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
      bufnr = res.bufnr,
      highlight = {
        border = 'DefinitionBorder',
        normal = 'DefinitionNormal',
      },
    }
    --@deprecated when 0.9 release
    if fn.has('nvim-0.9') == 1 and config.ui.title then
      self:title_text(opts, node.link)
    end

    node.prev = api.nvim_get_current_win()
    _, node.winid = window.create_win_with_border(content_opts, opts)
    if config.symbol_in_winbar.enable then
      api.nvim_win_set_var(node.winid, 'disable_winbar', true)
    end
    vim.opt_local.modifiable = true
    node.bufnr = res.bufnr
    node.wipe = res.wipe
    --set the initail cursor pos
    api.nvim_win_set_cursor(node.winid, { res.range.start.line + 1, res.range.start.character })
    vim.cmd('normal! zt')
    push(node)

    apply_aciton_keys({ res.range.start.line, res.range.start.character })

    api.nvim_create_autocmd('WinClosed', {
      group = group,
      buffer = node.bufnr,
      callback = function(opt)
        local curwinid = tonumber(opt.match)
        local index = find_node(curwinid)
        if index then
          local wins = fn.win_findbuf(opt.buf)
          wins = vim.tbl_filter(function(k)
            return find_node(k)
          end, wins)

          if #wins == 1 and wins[1] == curwinid then
            for _, map in pairs(config.definition) do
              api.nvim_buf_del_keymap(opt.buf, 'n', map)
            end
          end

          remove(index)
        end
      end,
    })
  end)
end

-- override the default the defintion handler
function def:goto_definition()
  lsp.handlers['textDocument/definition'] = function(_, result, _, _)
    if not result or vim.tbl_isempty(result) then
      return
    end
    local res = get_uri_data(result)
    if not res then
      return
    end
    vim.cmd('write')
    api.nvim_command('edit ' .. vim.uri_to_fname(res.uri))
    api.nvim_win_set_cursor(0, { res.range.start.line + 1, res.range.start.character })
    local width = #api.nvim_get_current_line()
    libs.jump_beacon({ res.range.start.line, res.range.start.character }, width)
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
