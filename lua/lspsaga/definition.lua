local config = require('lspsaga').config
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymap
local libs = require('lspsaga.libs')
local window = require('lspsaga.window')
local def = {}

-- a double linked list for store the node infor
local ctx = {}

local function clean_ctx()
  for i, _ in pairs(ctx) do
    ctx[i] = nil
  end
end

local function find_node(bufnr)
  for i, node in pairs(ctx) do
    if type(node) == 'table' and node.bufnr == bufnr then
      return i
    end
  end
end

local function push(node)
  ctx[#ctx + 1] = node
end

local function title_text(fname)
  if not fname then
    return
  end
  local title = {}
  local data = libs.icon_from_devicon(vim.bo.filetype)
  title[#title + 1] = { data[1], data[2] or 'TitleString' }
  title[#title + 1] = { fn.fnamemodify(fname, ':t'), 'TitleString' }

  return title
end

local function get_uri_data(result)
  local res = {}
  local range

  if type(result[1]) == 'table' then
    res.uri = result[1].uri or result[1].targetUri
    range = result[1].range or result[1].targetSelectionRange
  else
    res.uri = result.uri or result.targetUri
    range = result.range or result.targetSelectionRange
  end

  if not res.uri or not range then
    vim.notify('[Lspsaga] Did not find target uri', vim.log.levels.WARN)
    return
  end

  res.pos = { range.start.line, range.start.character }
  res.bufnr = vim.uri_to_bufnr(res.uri)

  if not api.nvim_buf_is_loaded(res.bufnr) then
    fn.bufload(res.bufnr)
    res.wipe = true
  end

  return res
end

function def:has_peek_win()
  if self.winid and api.nvim_win_is_valid(self.winid) then
    return true
  end
  return false
end

function def:apply_aciton_keys(buf, main_buf)
  local opt = { buffer = buf, nowait = true }
  local function find_node_index()
    local curbuf = api.nvim_get_current_buf()
    local index = find_node(curbuf)
    if not index then
      return
    end
    return index
  end

  for action, key in pairs(config.definition) do
    if action ~= 'quit' then
      keymap.set('n', key, function()
        local index = find_node_index()
        if not index then
          return
        end

        local node = ctx[index]
        api.nvim_win_close(self.winid, true)
        -- if buffer same as normal buffer write it first
        if node.bufnr == main_buf and vim.bo[node.bufnr].modified then
          vim.cmd('write!')
        end
        vim.cmd(action .. ' ' .. vim.uri_to_fname(node.uri))
        if not node.wipe then
          self.restore_opts.restore()
        end
        api.nvim_win_set_cursor(0, { node.pos[1] + 1, node.pos[2] })
        local width = #api.nvim_get_current_line()
        libs.jump_beacon({ node.pos[1], node.pos[2] }, width)
        clean_ctx()
      end, opt)
    end
  end

  keymap.set('n', '<C-o>', function()
    local index = find_node_index()
    if not index or not self:has_peek_win() then
      return
    end
    local prev = ctx[index - 1]
    if not prev then
      return
    end
    if not api.nvim_buf_is_valid(prev.bufnr) then
      prev.bufnr = vim.uri_to_bufnr(prev.uri)
      fn.bufload(prev.bufnr)
      self:apply_aciton_keys(prev.bufnr)
    end

    api.nvim_win_set_buf(self.winid, prev.bufnr)
    api.nvim_set_option_value(
      'winhl',
      'Normal:DefinitionNormal',
      { scope = 'local', win = self.winid }
    )
    api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.winid })
    api.nvim_win_set_cursor(self.winid, { prev.pos[1] + 1, prev.pos[2] })
    vim.cmd('normal! zz')
  end, opt)

  keymap.set('n', config.definition.quit, function()
    local index = find_node_index()
    if not index or not self:has_peek_win() then
      return
    end

    api.nvim_win_close(self.winid, true)
    for _, node in pairs(ctx) do
      if type(node) == 'table' then
        vim.tbl_map(function(k)
          pcall(api.nvim_buf_del_keymap, node.bufnr, 'n', k)
        end, config.definition)
      end
    end

    clean_ctx()
  end, opt)
end

local function get_method(index)
  local tbl = { 'textDocument/definition', 'textDocument/typeDefinition' }
  return tbl[index]
end

local function create_window(node)
  local cur_winline = fn.winline()
  local max_height = math.floor(vim.o.lines * 0.5)
  local max_width = math.floor(vim.o.columns * 0.6)
  def.restore_opts = window.restore_option()

  local opt = {
    relative = 'cursor',
    no_override_size = true,
    height = max_height,
    width = max_width,
  }
  if vim.o.lines - opt.height - cur_winline < 0 then
    vim.cmd('normal! zz')
    local keycode = api.nvim_replace_termcodes('5<C-e>', true, false, true)
    api.nvim_feedkeys(keycode, 'x', false)
  end

  local content_opts = {
    contents = {},
    enter = true,
    highlight = {
      border = 'DefinitionBorder',
      normal = 'DefinitionNormal',
    },
  }
  --@deprecated when 0.9 release
  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = title_text(vim.uri_to_fname(node.uri))
  end

  return window.create_win_with_border(content_opts, opt)
end

local in_process = 0

function def:peek_definition(method)
  local cur_winid = api.nvim_get_current_win()
  if in_process == cur_winid then
    vim.notify('[Lspsaga] Already have a peek_definition request please wait', vim.log.levels.WARN)
    return
  end

  in_process = cur_winid
  local current_buf = api.nvim_get_current_buf()

  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  local current_word = fn.expand('<cword>')
  local from = { current_buf, pos[1], pos[2] + 1, 0 }
  local items = { { tagname = current_word, from = from } }
  fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

  local params = lsp.util.make_position_params()
  local method_name = get_method(method)

  lsp.buf_request_all(current_buf, method_name, params, function(results)
    in_process = 0
    if not results or next(results) == nil then
      vim.notify(
        '[Lspsaga] response of request method ' .. method_name .. ' is nil',
        vim.log.levels.WARN
      )
      return
    end

    local result
    for _, res in pairs(results) do
      if res and res.result and not vim.tbl_isempty(res.result) then
        result = res.result
      end
    end

    if not result then
      vim.notify(
        '[Lspsaga] response of request method ' .. method_name .. ' is nil',
        vim.log.levels.WARN
      )
      return
    end

    local node = get_uri_data(result)
    if not node or not node.bufnr then
      return
    end

    if not self.winid or not api.nvim_win_is_valid(self.winid) then
      _, self.winid = create_window(node)
    end
    api.nvim_win_set_buf(self.winid, node.bufnr)
    api.nvim_set_option_value(
      'winhl',
      'Normal:DefinitionNormal,FloatBorder:DefinitionBorder',
      { scope = 'local', win = self.winid }
    )
    api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.winid })

    if node.wipe then
      api.nvim_set_option_value('bufhidden', 'wipe', { buf = node.bufnr })
    end

    vim.bo[node.bufnr].modifiable = true
    --set the initail cursor pos
    api.nvim_win_set_cursor(self.winid, { node.pos[1] + 1, node.pos[2] })
    vim.cmd('normal! zt')
    push(node)

    self:apply_aciton_keys(node.bufnr, current_buf)
  end)
end

-- override the default the defintion handler
function def:goto_definition(method)
  lsp.handlers[get_method(method)] = function(_, result, _, _)
    if not result or vim.tbl_isempty(result) then
      return
    end
    local res = {}

    if type(result[1]) == 'table' then
      res.uri = result[1].uri or result[1].targetUri
      res.range = result[1].range or result[1].targetSelectionRange
    else
      res.uri = result.uri or result.targetUri
      res.range = result.range or result.targetSelectionRange
    end

    if vim.tbl_isempty(res) then
      return
    end

    local jump_destination = vim.uri_to_fname(res.uri)
    local current_buffer = api.nvim_buf_get_name(0)

    -- if the current buffer is the jump destination and it has been modified
    -- then write the changes first.
    -- this is needed because if the definition is in the current buffer the
    -- jump may not go to the right place.
    if vim.bo.modified and current_buffer == jump_destination then
      vim.cmd('write!')
    end

    api.nvim_command('edit ' .. jump_destination)

    api.nvim_win_set_cursor(0, { res.range.start.line + 1, res.range.start.character })
    local width = #api.nvim_get_current_line()
    libs.jump_beacon({ res.range.start.line, res.range.start.character }, width)
  end
  if method == 1 then
    lsp.buf.definition()
  elseif method == 2 then
    lsp.buf.type_definition()
  end
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
