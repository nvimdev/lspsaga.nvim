local ui = require('lspsaga').config.ui
local api = vim.api

local resolved

local function init_kind()
  local kind = {
    [1] = { 'File', ' ', 'Tag' },
    [2] = { 'Module', ' ', 'Exception' },
    [3] = { 'Namespace', ' ', 'Include' },
    [4] = { 'Package', ' ', 'Label' },
    [5] = { 'Class', ' ', 'Include' },
    [6] = { 'Method', ' ', 'Function' },
    [7] = { 'Property', ' ', '@property' },
    [8] = { 'Field', ' ', '@field' },
    [9] = { 'Constructor', ' ', '@constructor' },
    [10] = { 'Enum', '了', '@number' },
    [11] = { 'Interface', ' ', 'Type' },
    [12] = { 'Function', ' ', 'Function' },
    [13] = { 'Variable', ' ', '@variable' },
    [14] = { 'Constant', ' ', 'Constant' },
    [15] = { 'String', ' ', 'String' },
    [16] = { 'Number', ' ', 'Number' },
    [17] = { 'Boolean', ' ', 'Boolean' },
    [18] = { 'Array', ' ', 'Type' },
    [19] = { 'Object', ' ', 'Type' },
    [20] = { 'Key', ' ', '' },
    [21] = { 'Null', ' ', 'Constant' },
    [22] = { 'EnumMember', ' ', 'Number' },
    [23] = { 'Struct', ' ', 'Type' },
    [24] = { 'Event', ' ', 'Constant' },
    [25] = { 'Operator', ' ', 'Operator' },
    [26] = { 'TypeParameter', ' ', 'Type' },
    -- ccls
    [252] = { 'TypeAlias', ' ', 'Type' },
    [253] = { 'Parameter', ' ', '@parameter' },
    [254] = { 'StaticMethod', 'ﴂ ', 'Function' },
    [255] = { 'Macro', ' ', 'Macro' },
    -- for completion sb microsoft!!!
    [300] = { 'Text', ' ', 'String' },
    [301] = { 'Snippet', ' ', '@variable' },
    [302] = { 'Folder', ' ', '@parameter' },
    [303] = { 'Unit', ' ', 'Number' },
    [304] = { 'Value', ' ', '@variable' },
  }

  local function find_index_by_type(k)
    for index, opts in pairs(kind) do
      if opts[1] == k then
        return index
      end
    end
    return nil
  end

  for k, v in pairs(ui.kind) do
    local index = find_index_by_type(k)
    if not index then
      vim.notify('[lspsaga.nvim] could not find kind in default')
      return
    end
    if type(v) == 'table' then
      kind[index][2], kind[index][3] = unpack(v)
    elseif type(v) == 'string' then
      kind[index][2] = v
    else
      vim.notify('[Lspsaga.nvim] value must be string or table')
    end
  end

  resolved = function()
    return kind
  end
end

local function gen_symbol_winbar_hi(kind)
  local prefix = 'SagaWinbar'
  local winbar_sep = 'SagaWinbarSep'

  for _, v in pairs(kind) do
    api.nvim_set_hl(0, prefix .. v[1], { link = v[3] })
  end
  api.nvim_set_hl(0, winbar_sep, { fg = '#ee4866', default = true })
  api.nvim_set_hl(0, prefix .. 'FileName', { link = 'Comment', default = true })
  api.nvim_set_hl(0, prefix .. 'Word', { link = 'Operator', default = true })
  api.nvim_set_hl(0, prefix .. 'FolderName', { link = 'Operator', default = true })
end

local function init_kind_hl()
  if not resolved then
    init_kind()
  end
  local kind = resolved()
  gen_symbol_winbar_hi(kind)
end

local function get_kind()
  return resolved()
end

return {
  init_kind_hl = init_kind_hl,
  get_kind = get_kind,
}
