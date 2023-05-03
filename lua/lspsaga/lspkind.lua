local ui = require('lspsaga').config.ui
local api = vim.api

local function merge_custom(kind)
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
      kind[index][3] = v
    else
      vim.notify('[Lspsaga.nvim] value must be string or table')
    end
  end
end

local function get_kind()
  local kind = {
    [1] = { 'File', ' ', 'Tag' },
    [2] = { 'Module', ' ', 'Exception' },
    [3] = { 'Namespace', ' ', 'Include' },
    [4] = { 'Package', ' ', 'Label' },
    [5] = { 'Class', ' ', 'Include' },
    [6] = { 'Method', ' ', 'Function' },
    [7] = { 'Property', ' ', '@property' },
    [8] = { 'Field', ' ', '@field' },
    [9] = { 'Constructor', ' ', '@constructor' },
    [10] = { 'Enum', ' ', '@number' },
    [11] = { 'Interface', ' ', 'Type' },
    [12] = { 'Function', '󰊕', 'Function' },
    [13] = { 'Variable', ' ', '@variable' },
    [14] = { 'Constant', ' ', 'Constant' },
    [15] = { 'String', '󰅳 ', 'String' },
    [16] = { 'Number', '󰎠 ', 'Number' },
    [17] = { 'Boolean', ' ', 'Boolean' },
    [18] = { 'Array', '󰅨 ', 'Type' },
    [19] = { 'Object', ' ', 'Type' },
    [20] = { 'Key', ' ', 'Constant' },
    [21] = { 'Null', '󰟢 ', 'Constant' },
    [22] = { 'EnumMember', ' ', 'Number' },
    [23] = { 'Struct', ' ', 'Type' },
    [24] = { 'Event', ' ', 'Constant' },
    [25] = { 'Operator', ' ', 'Operator' },
    [26] = { 'TypeParameter', ' ', 'Type' },
    -- ccls
    [252] = { 'TypeAlias', ' ', 'Type' },
    [253] = { 'Parameter', ' ', '@parameter' },
    [254] = { 'StaticMethod', ' ', 'Function' },
    [255] = { 'Macro', ' ', 'Macro' },
    -- for completion sb microsoft!!!
    [300] = { 'Text', '󰭷 ', 'String' },
    [301] = { 'Snippet', ' ', '@variable' },
    [302] = { 'Folder', ' ', 'Title' },
    [303] = { 'Unit', '󰊱 ', 'Number' },
    [304] = { 'Value', ' ', '@variable' },
  }

  merge_custom(kind)
  return kind
end

local function other_groups()
  local prefix = 'SagaWinbar'
  return { prefix .. 'Filename', prefix .. 'FolderName' }
end

local function get_kind_group()
  local prefix = 'SagaWinbar'
  local res = {}
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, item in pairs(get_kind()) do
    res[#res + 1] = prefix .. item[1]
  end
  res = vim.list_extend(res, other_groups())
  res[#res + 1] = 'SagaWinbarFileIcon'
  res[#res + 1] = 'SagaWinbarSep'
  return res
end

local function find_kind_group(name)
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, v in pairs(get_kind()) do
    if name:find(v[1]) then
      return v[3]
    end
  end
end

local function init_kind_hl()
  local others = other_groups()
  local tbl = get_kind_group()
  ---@diagnostic disable-next-line: param-type-mismatch
  for i, v in pairs(tbl) do
    if vim.tbl_contains(others, v) then
      api.nvim_set_hl(0, v, { fg = '#bdbfb8', default = true })
    elseif i == #tbl then
      api.nvim_set_hl(0, v, { link = 'Operator', default = true })
    else
      local group = find_kind_group(v)
      api.nvim_set_hl(0, v, { link = group, default = true })
    end
  end
end

return {
  init_kind_hl = init_kind_hl,
  get_kind = get_kind,
  get_kind_group = get_kind_group,
}
