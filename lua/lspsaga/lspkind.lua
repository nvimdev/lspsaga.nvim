local api = vim.api

local colors = {
  fg = '#bbc2cf',
  red = '#e95678',
  orange = '#FF8700',
  yellow = '#f7bb3b',
  green = '#afd700',
  cyan = '#36d0e0',
  blue = '#61afef',
  violet = '#CBA6F7',
}

local kind = {
	[1]  = { "File"," ",colors.fg},
	[2]  = { "Module"," ",colors.blue},
	[3]  = { "Namespace"," ",colors.orange},
	[4]  = { "Package"," ",colors.violet},
	[5]  = { "Class"," ",colors.violet},
	[6]  = { "Method"," ",colors.violet},
	[7]  = { "Property"," ",colors.cyan},
	[8]  = { "Field"," ",colors.cyan},
	[9]  = { "Constructor"," ",colors.blue},
	[10] = { "Enum","了",colors.green},
	[11] = { "Interface","練",colors.orange},
	[12] = { "Function"," ",colors.violet},
	[13] = { "Variable"," ",colors.blue},
	[14] = { "Constant"," ",colors.cyan},
	[15] = { "String"," ",colors.green},
	[16] = { "Number"," ",colors.green},
	[17] = { "Boolean","◩ ",colors.orange},
	[18] = { "Array"," ",colors.blue},
	[19] = { "Object"," ",colors.orange},
	[20] = { "Key"," ",colors.red},
	[21] = { "Null","ﳠ ",colors.red},
	[22] = { "EnumMember"," ",colors.green},
	[23] = { "Struct"," ",colors.violet},
	[24] = { "Event"," ",colors.violet},
	[25] = { "Operator"," ",colors.green},
	[26] = { "TypeParameter"," ",colors.green},
}

local function gen_symbol_winbar_hi()
  local prefix = 'LspSagaWinbar'
  local winbar_sep = 'LspSagaWinbarSep'
  for _,v in pairs(kind) do
    api.nvim_set_hl(0,prefix..v[1],{ fg = v[3] })
  end
  api.nvim_set_hl(0,winbar_sep,{fg = '#d16d9e'})
  api.nvim_set_hl(0,prefix..'File',{fg = colors.fg,bold = true})
end

kind = setmetatable(kind,{
  __index = function(_,key)
    if key == 'gen_symbol_winbar_hi' then
      return gen_symbol_winbar_hi
    end
  end
})

return kind
