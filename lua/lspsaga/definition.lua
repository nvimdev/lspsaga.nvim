local config = require('lspsaga').config
local lsp, fn, api = vim.lsp, vim.fn, vim.api
local util = require('lspsaga.util')
local win = require('lspsaga.window')
local buf_del_keymap = api.nvim_buf_del_keymap
local beacon = require('lspsaga.beacon').jump_beacon
local def = {}
def.__index = def

-- a double linked list for store the node infor
local ctx = {}

local IS_PEEK = 1
local IS_GOTO = 2

local function clean_ctx()
  for i, _ in pairs(ctx) do
    ctx[i] = nil
  end
end

local function get_method(index)
  local tbl = { 'textDocument/definition', 'textDocument/typeDefinition' }
  return tbl[index]
end

local function get_node_idx(list, winid)
  for i, node in ipairs(list) do
    if node.winid == winid then
      return i
    end
  end
end

local function in_def_wins(list, bufnr)
  local wins = fn.win_findbuf(bufnr)
  local in_def = false
  for _, id in ipairs(wins) do
    if get_node_idx(list, id) then
      in_def = true
      break
    end
  end
  return in_def
end

function def:close_all()
  vim.opt.eventignore:append('WinClosed')
  local function recursive(tbl)
    local node = tbl[#tbl]
    if api.nvim_win_is_valid(node.winid) then
      api.nvim_win_close(node.winid, true)
    end
    if not node.wipe and not in_def_wins(tbl, node.bufnr) then
      self:delete_maps(node.bufnr)
    end
    table.remove(tbl, #tbl)
    if #tbl ~= 0 then
      recursive(tbl)
    end
  end
  recursive(self.list)
  clean_ctx()
  vim.opt.eventignore:remove('WinClosed')
  api.nvim_del_augroup_by_name('SagaPeekdefinition')
end

function def:apply_maps(bufnr)
  for action, map in pairs(config.definition.keys) do
    if action ~= 'close' then
      util.map_keys(bufnr, map, function()
        local fname = api.nvim_buf_get_name(0)
        local index = get_node_idx(self.list, api.nvim_get_current_win())
        local start = self.list[index].selectionRange.start
        local client = lsp.get_client_by_id(self.list[index].client_id)
        if not client then
          return
        end
        if action == 'quit' then
          vim.cmd[action]()
          return
        end
        local restore = self.opt_restore
        self:close_all()
        local curbuf = api.nvim_get_current_buf()
        if action ~= 'edit' or curbuf ~= bufnr then
          vim.cmd[action](fname)
        end
        restore()
        api.nvim_win_set_cursor(0, {
          start.line + 1,
          lsp.util._get_line_byte_from_position(0, start, client.offset_encoding),
        })
        local width = #api.nvim_get_current_line()
        beacon({ start.line, vim.fn.col('.') }, width)
      end)
    else
      util.map_keys(bufnr, map, function()
        self:close_all()
      end)
    end
  end
end

function def:delete_maps(bufnr)
  for _, map in pairs(config.definition.keys) do
    for _, key in ipairs(util.as_table(map)) do
      pcall(buf_del_keymap, bufnr, 'n', key)
    end
  end
end

function def:create_win(bufnr, root_dir)
  local fname = api.nvim_buf_get_name(bufnr)
  fname = util.path_sub(fname, root_dir)
  if not self.list or vim.tbl_isempty(self.list) then
    local float_opt = {
      width = math.floor(api.nvim_win_get_width(0) * config.definition.width),
      height = math.floor(api.nvim_win_get_height(0) * config.definition.height),
      bufnr = bufnr,
    }
    if config.ui.title then
      float_opt.title = fname
      float_opt.title_pos = 'center'
    end
    return win
      :new_float(float_opt, true)
      :winopt({
        ['winbar'] = '',
        ['signcolumn'] = 'no',
      })
      :winhl('SagaNormal', 'SagaBorder')
      :wininfo()
  end
  local win_conf = api.nvim_win_get_config(self.list[#self.list].winid)
  win_conf.bufnr = bufnr
  win_conf.title = fname
  win_conf.row = win_conf.row[false] + 1
  win_conf.col = win_conf.col[false] + 1
  win_conf.height = win_conf.height - 1
  win_conf.width = win_conf.width - 2
  return win:new_float(win_conf, true, true):wininfo()
end

function def:clean_event()
  api.nvim_create_autocmd('WinClosed', {
    group = api.nvim_create_augroup('SagaPeekdefinition', { clear = true }),
    callback = function(args)
      local curwin = tonumber(args.match)
      local index = get_node_idx(self.list, curwin)
      if not index then
        return
      end
      local bufnr = self.list[index].bufnr

      if self.list[index].restore then
        self.opt_restore()
      end
      local prev = self.list[index - 1] and self.list[index - 1] or nil
      table.remove(self.list, index)
      if prev then
        api.nvim_set_current_win(prev.winid)
      end

      if api.nvim_buf_is_loaded(bufnr) then
        if not in_def_wins(self.list, bufnr) then
          self:delete_maps(bufnr)
        end
      end

      if not self.list or #self.list == 0 then
        clean_ctx()
        api.nvim_del_autocmd(args.id)
      end
    end,
    desc = '[lspsaga] peek definition clean data event',
  })
end

function def:definition_request(method, handler_T, args)
  if self.pending_reqeust then
    vim.notify(
      '[lspsaga] a peek_definition request has already been sent, please wait.',
      vim.log.levels.WARN
    )
    return
  end

  if not self.list then
    self.list = {}
    self:clean_event()
  end

  local current_buf = api.nvim_get_current_buf()

  local params = lsp.util.make_position_params()
  self.opt_restore = win:minimal_restore()
  self.pending_request = true
  local count = #util.get_client_by_method(method)

  lsp.buf_request(current_buf, method, params, function(_, result, context)
    if not result or #result == 0 then
      return
    end

    --set jumplist
    -- vim.cmd("normal! m'")
    -- --
    -- -- -- push a tag stack
    -- local pos = api.nvim_win_get_cursor(0)
    -- local current_word = fn.expand('<cword>')
    -- local from = { current_buf, pos[1], pos[2] + 1, 0 }
    -- local items = { { tagname = current_word, from = from } }
    -- fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

    if handler_T == IS_PEEK then
      return self:peek_handler(result, context, count)
    end
    if handler_T == IS_GOTO then
      return self:goto_handler(result, context, args)
    end
  end)
end

function def:peek_handler(result, context, count)
  count = count - 1
  self.pending_request = false
  if not result or next(result) == nil then
    if #self.list == 0 and count == 0 then
      vim.notify(
        '[lspsaga] response of request method ' .. context.method .. ' is empty',
        vim.log.levels.WARN
      )
    end
    return
  end
  if result.uri then
    result = { result }
  end

  local node = {
    bufnr = vim.uri_to_bufnr(result[1].targetUri or result[1].uri),
    selectionRange = result[1].targetSelectionRange or result[1].range,
    client_id = context.client_id,
  }
  if not api.nvim_buf_is_loaded(node.bufnr) then
    fn.bufload(node.bufnr)
    api.nvim_set_option_value('bufhidden', 'wipe', { buf = node.bufnr })
    node.wipe = true
  end
  local root_dir = lsp.get_client_by_id(context.client_id).config.root_dir
  _, node.winid = self:create_win(node.bufnr, root_dir)
  local client = lsp.get_client_by_id(context.client_id)
  if not client then
    return
  end
  api.nvim_win_set_cursor(node.winid, {
    node.selectionRange.start.line + 1,
    lsp.util._get_line_byte_from_position(
      node.bufnr,
      node.selectionRange.start,
      client.offset_encoding
    ),
  })
  self:apply_maps(node.bufnr)
  self.list[#self.list + 1] = node
end

-- override the default the defintion handler
function def:goto_handler(result, context, args)
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
  local client = lsp.get_client_by_id(context.client_id)

  if vim.tbl_isempty(res) or not client then
    return
  end

  local target_bufnr = vim.uri_to_bufnr(res.uri)
  if not api.nvim_buf_is_loaded(target_bufnr) then
    vim.fn.bufload(target_bufnr)
  end
  if args and #args > 0 then
    vim.cmd[args[1]]()
  end
  api.nvim_win_set_buf(0, target_bufnr)

  api.nvim_win_set_cursor(0, {
    res.range.start.line + 1,
    lsp.util._get_line_byte_from_position(target_bufnr, res.range.start, client.offset_encoding),
  })
  local width = #api.nvim_get_current_line()
  beacon({ res.range.start.line, vim.fn.col('.') }, width)
end

function def:init(method, jump_T, args)
  local t = jump_T == IS_PEEK and IS_PEEK or IS_GOTO
  self:definition_request(get_method(method), t, args)
end

return setmetatable(ctx, def)
