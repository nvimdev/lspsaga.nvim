local api = vim.api
local custom_kind = require('lspsaga').config_values.custom_kind

local colors = {
  fg = '#bbc2cf',
  red = '#e95678',
  orange = '#FF8700',
  yellow = '#f7bb3b',
  green = '#afd700',
  cyan = '#36d0e0',
  blue = '#61afef',
  violet = '#CBA6F7',
  teal = '#1abc9c',
}

local kind = {
  [1] = { 'File', ' ', colors.fg },
  [2] = { 'Module', ' ', colors.blue },
  [3] = { 'Namespace', ' ', colors.orange },
  [4] = { 'Package', ' ', colors.violet },
  [5] = { 'Class', ' ', colors.violet },
  [6] = { 'Method', ' ', colors.violet },
  [7] = { 'Property', ' ', colors.cyan },
  [8] = { 'Field', ' ', colors.teal },
  [9] = { 'Constructor', ' ', colors.blue },
  [10] = { 'Enum', '了', colors.green },
  [11] = { 'Interface', ' ', colors.orange },
  [12] = { 'Function', ' ', colors.violet },
  [13] = { 'Variable', ' ', colors.blue },
  [14] = { 'Constant', ' ', colors.cyan },
  [15] = { 'String', ' ', colors.green },
  [16] = { 'Number', ' ', colors.green },
  [17] = { 'Boolean', ' ', colors.orange },
  [18] = { 'Array', ' ', colors.blue },
  [19] = { 'Object', ' ', colors.orange },
  [20] = { 'Key', ' ', colors.red },
  [21] = { 'Null', ' ', colors.red },
  [22] = { 'EnumMember', ' ', colors.green },
  [23] = { 'Struct', ' ', colors.violet },
  [24] = { 'Event', ' ', colors.violet },
  [25] = { 'Operator', ' ', colors.green },
  [26] = { 'TypeParameter', ' ', colors.green },
  -- ccls
  [252] = { 'TypeAlias', ' ', colors.green },
  [253] = { 'Parameter', ' ', colors.blue },
  [254] = { 'StaticMethod', 'ﴂ ', colors.orange },
  [255] = { 'Macro', ' ', colors.red },
}

local function find_index_by_type(k)
  for index, opts in pairs(kind) do
    if opts[1] == k then
      return index
    end
  end
  return nil
end

local function load_custom_kind()
  if next(custom_kind) ~= nil then
    for k, conf in pairs(custom_kind) do
      local index = find_index_by_type(k)
      if not index then
        vim.notify('Does not find this type in kind')
      end

      if type(conf) == 'string' then
        kind[index][3] = conf
      end

      if type(conf) == 'table' then
        kind[index][2] = conf[1]
        kind[index][3] = conf[2]
      end
    end
  end
end

local function gen_symbol_winbar_hi()
  local prefix = 'LspSagaWinbar'
  local winbar_sep = 'LspSagaWinbarSep'

  for _, v in pairs(kind) do
    api.nvim_set_hl(0, prefix .. v[1], { fg = v[3] })
  end
  api.nvim_set_hl(0, winbar_sep, { fg = '#d16d9e' })
  api.nvim_set_hl(0, prefix .. 'File', { fg = colors.fg, bold = true })
end

kind = setmetatable(kind, {
  __index = function(_, key)
    if key == 'gen_symbol_winbar_hi' then
      return gen_symbol_winbar_hi
    end

    if key == 'load_custom_kind' then
      return load_custom_kind
    end

    if key == 'colors' then
      return colors
    end
  end,
})

return kind
