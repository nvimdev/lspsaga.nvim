local api = vim.api
local saga = {}

saga.config_values = {
  debug = false,
  -- Error,Warn,Info,Hint
  diagnostic_header_icon = {' ',' ',' ','ﴞ '},
  -- code action title icon
  code_action_icon = '💡',
  -- if true can press number to execute the codeaction in codeaction window
  code_action_num_shortcut = true,
  code_action_lightbulb = {
    enable = true,
    sign = true,
    sign_priority = 40,
    virtual_text = true,
  },
  finder_definition_icon = '  ',
  finder_reference_icon = '  ',
  max_preview_lines = 10,
  finder_action_keys = {
    open = 'o', vsplit = 's',split = 'i',quit = 'q',
    scroll_down = '<C-f>',scroll_up = '<C-b>'
  },
  code_action_keys = {
    quit = 'q',exec = '<CR>'
  },
  rename_action_quit = '<C-c>',
  definition_preview_icon = '  ',
  border_style = "single",
  server_filetype_map = {}
}

local extend_config = function(opts)
  opts = opts or {}
  if next(opts) == nil then return  end
  for key,value in pairs(opts) do
    if saga.config_values[key] == nil then
      error(string.format('[LspSaga] Key %s not exist in config values',key))
      return
    end
    if type(saga.config_values[key]) == 'table' then
      for k,v in pairs(value) do
        saga.config_values[key][k] = v
      end
    else
      saga.config_values[key] = value
    end
  end
end

function saga.init_lsp_saga(opts)
  extend_config(opts)
  if saga.config_values.code_action_lightbulb.enable then
    api.nvim_create_autocmd({'CursorHold','CursorHoldI'},{
      pattern = '*',
      callback = require('lspsaga.lightbulb').action_lightbulb
    })
  end
end

return saga
