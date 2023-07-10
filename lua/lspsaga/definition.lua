local config = require('lspsaga').config
local lsp, fn, api = vim.lsp, vim.fn, vim.api
local log = require('lspsaga.logger')
local util = require('lspsaga.util')
local win = require('lspsaga.window')
local buf_del_keymap = api.nvim_buf_del_keymap
local beacon = require('lspsaga.beacon').jump_beacon
local def = {}
def.__index = def

-- a double linked list for store the node infor
local ctx = {}

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
end

function def:apply_maps(bufnr)
  for action, map in pairs(config.definition.keys) do
    if action ~= 'close' then
      util.map_keys(bufnr, map, function()
        local fname = api.nvim_buf_get_name(0)
        local index = get_node_idx(self.list, api.nvim_get_current_win())
        local pos = {
          self.list[index].selectionRange.start.line + 1,
          self.list[index].selectionRange.start.character,
        }
        if action == 'quit' then
          vim.cmd[action]()
          return
        end
        self:close_all()
        vim.cmd[action](fname)
        api.nvim_win_set_cursor(0, pos)
        beacon({ pos[1] - 1, 0 }, #api.nvim_get_current_line())
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
    buf_del_keymap(bufnr, 'n', map)
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
      :winopt('winbar', '')
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
      local curwin = tonumber(args.file)
      local index = get_node_idx(self.list or {}, curwin)
      if not index then
        return
      end

      if self.list[index].restore then
        self.opt_restore()
      end
      local prev = self.list[index - 1] and self.list[index - 1] or nil
      table.remove(self.list, index)
      if prev then
        api.nvim_set_current_win(prev.winid)
      end

      if api.nvim_buf_is_loaded(args.buf) then
        if not in_def_wins(self.list, args.buf) then
          self:delete_maps(args.buf)
        end
      end

      if not self.list or #self.list == 0 then
        clean_ctx()
        api.nvim_del_autocmd(args.id)
      end
    end,
    desc = '[Lspsaga] peek definition clean data event',
  })
end

function def:peek_definition(method)
  if self.pending_reqeust then
    vim.notify(
      '[Lspsaga] There is already a peek_definition request, please wait for the response.',
      vim.log.levels.WARN
    )
    return
  end

  if not self.list then
    self.list = {}
    self:clean_event()
  end

  local current_buf = api.nvim_get_current_buf()

  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  local current_word = fn.expand('<cword>')
  local from = { current_buf, pos[1], pos[2] + 1, 0 }
  local items = { { tagname = current_word, from = from } }
  fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

  local params = lsp.util.make_position_params()
  local method_name = get_method(method)
  self.opt_restore = win:minimal_restore()

  self.pending_request = true
  lsp.buf_request(current_buf, method_name, params, function(_, result, context)
    self.pending_request = false
    if not result or next(result) == nil then
      vim.notify(
        '[Lspsaga] response of request method ' .. method_name .. ' is empty',
        vim.log.levels.WARN
      )
      return
    end

    local node = {
      bufnr = vim.uri_to_bufnr(result[1].targetUri or result[1].uri),
      selectionRange = result[1].targetSelectionRange or result[1].range,
    }
    if not api.nvim_buf_is_loaded(node.bufnr) then
      fn.bufload(node.bufnr)
      api.nvim_set_option_value('bufhidden', 'wipe', { buf = node.bufnr })
      node.wipe = true
    end
    local root_dir = lsp.get_client_by_id(context.client_id).config.root_dir
    _, node.winid = self:create_win(node.bufnr, root_dir)
    api.nvim_win_set_cursor(
      node.winid,
      { node.selectionRange.start.line + 1, node.selectionRange.start.character }
    )
    beacon(
      { node.selectionRange.start.line, node.selectionRange.start.character },
      #api.nvim_get_current_line()
    )
    self:apply_maps(node.bufnr)
    self.list[#self.list + 1] = node
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
    beacon({ res.range.start.line, res.range.start.character }, width)
  end
  if method == 1 then
    lsp.buf.definition()
  elseif method == 2 then
    lsp.buf.type_definition()
  end
end

return setmetatable(ctx, def)
