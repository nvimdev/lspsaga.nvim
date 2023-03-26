local ui = require('lspsaga').config.ui

local function theme()
  local symbols = {
    arrow = {
      left = '',
      right = '',
    },
    none = {
      left = '',
      right = '',
    },
    round = {
      left = '',
      right = '',
    },
    slant = {
      left = '',
      right = '',
    },
  }
  return symbols[ui.theme]
end

return {
  theme = theme,
}
