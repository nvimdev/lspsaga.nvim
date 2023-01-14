local ui = require('lspsaga').config.ui

local resolved = nil

local function get_kind(colors)
  if resolved then
    return resolved
  end
  local kind = {
    [1] = { 'File', ' ', colors.white },
    [2] = { 'Module', ' ', colors.blue },
    [3] = { 'Namespace', ' ', colors.orange },
    [4] = { 'Package', ' ', colors.purple },
    [5] = { 'Class', ' ', colors.purple },
    [6] = { 'Method', ' ', colors.purple },
    [7] = { 'Property', ' ', colors.cyan },
    [8] = { 'Field', ' ', colors.teal },
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

  if not vim.tbl_isempty(ui.kind) then
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
      kind[index][2] = v
    end
  end

  resolved = function()
    return kind
  end

  return resolved
end

return {
  get_kind = get_kind,
}
