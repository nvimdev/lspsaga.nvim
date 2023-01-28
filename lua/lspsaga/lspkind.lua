local ui = require('lspsaga').config.ui
local api = vim.api

local function get_kind(custom)
  local colors = require('lspsaga.highlight').get_colors()
  local kind = {
    [1] = { 'File', ' ', colors.white },
    [2] = { 'Module', ' ', colors.blue },
    [3] = { 'Namespace', ' ', colors.orange },
    [4] = { 'Package', ' ', colors.purple },
    [5] = { 'Class', ' ', colors.purple },
    [6] = { 'Method', ' ', colors.purple },
    [7] = { 'Property', ' ', colors.cyan },
    [8] = { 'Field', ' ', colors.yellow },
    [9] = { 'Constructor', ' ', colors.blue },
    [10] = { 'Enum', '了', colors.green },
    [11] = { 'Interface', ' ', colors.orange },
    [12] = { 'Function', ' ', colors.purple },
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
    [23] = { 'Struct', ' ', colors.purple },
    [24] = { 'Event', ' ', colors.purple },
    [25] = { 'Operator', ' ', colors.green },
    [26] = { 'TypeParameter', ' ', colors.green },
    -- ccls
    [252] = { 'TypeAlias', ' ', colors.green },
    [253] = { 'Parameter', ' ', colors.blue },
    [254] = { 'StaticMethod', 'ﴂ ', colors.orange },
    [255] = { 'Macro', ' ', colors.red },
    -- for completion sb microsoft!!!
    [300] = { 'Text', ' ', colors.green },
    [301] = { 'Snippet', ' ', colors.blue },
    [302] = { 'Folder', ' ', colors.yellow },
    [303] = { 'Unit', ' ', colors.cyan },
    [304] = { 'Value', ' ', colors.blue },
  }

  if custom and not vim.tbl_isempty(custom) then
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
        vim.notify('[lspsaga.nvim] not found kind in default')
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
  end
  return kind
end

local function gen_symbol_winbar_hi(kind)
  local prefix = 'LspSagaWinbar'
  local winbar_sep = 'LspSagaWinbarSep'
  local colors = require('lspsaga.highlight').get_colors()

  for _, v in pairs(kind or {}) do
    api.nvim_set_hl(0, prefix .. v[1], { fg = v[3] })
  end
  api.nvim_set_hl(0, winbar_sep, { fg = colors.red, default = true })
  api.nvim_set_hl(0, prefix .. 'File', { fg = colors.fg, default = true })
  api.nvim_set_hl(0, prefix .. 'Word', { fg = colors.white, default = true })
  api.nvim_set_hl(0, prefix .. 'FolderName', { fg = colors.fg, default = true })
end

local function gen_outline_hi(kind)
  for _, v in pairs(kind or {}) do
    local hi_name = 'LSOutline' .. v[1]
    local ok, tbl = pcall(api.nvim_get_hl_by_name, hi_name, true)
    if not ok or not tbl.foreground then
      api.nvim_set_hl(0, hi_name, { fg = v[3] })
    end
  end
end

local function init_or_reload(custom)
  local kind = get_kind(custom)
  gen_outline_hi(kind)
  gen_symbol_winbar_hi(kind)
end

return {
  init_or_reload = init_or_reload,
  get_kind = get_kind,
}
