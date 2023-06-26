local config = require('lspsaga').config
local lsp, fn, api, keymap = vim.lsp, vim.fn, vim.api, vim.keymapdef
local log = require('lspsaga.logger')
local util = require('lspsaga.util')
local window = require('lspsaga.window')
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
local def = {}

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

function def:apply_aciton_keys(buf, main_buf) end
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

  self.pending_request = true
  lsp.buf_request(current_buf, method_name, params, function(_, result)
    self.pending_request = false
    if not result or next(result) == nil then
      vim.notify(
        '[Lspsaga] response of request method ' .. method_name .. ' is nil',
        vim.log.levels.WARN
      )
      return
    end
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
    util.jump_beacon({ res.range.start.line, res.range.start.character }, width)
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
  __index = function(_, k)
    return ctx[k]
  end,
})

return def
