local saga = {}

saga.config_values = {
  debug = false,
  use_saga_diagnostic_sign = true,
  -- diagnostic sign
  error_sign = "",
  warn_sign = "",
  hint_sign = "",
  infor_sign = "",
  diagnostic_header_icon = "   ",
  -- diagnostic_show_source = true,
  -- diagnostic_show_code = true,
  -- code action title icon
  code_action_icon = " ",
  code_action_prompt = {
    enable = true,
    sign = true,
    sign_priority = 40,
    virtual_text = true,
  },
  finder_definition_icon = "  ",
  finder_reference_icon = "  ",
  max_preview_lines = 10,
  finder_action_keys = {
    open = "o",
    vsplit = "s",
    split = "i",
    quit = "q",
    scroll_down = "<C-f>",
    scroll_up = "<C-b>",
  },
  code_action_keys = {
    quit = "q",
    exec = "<CR>",
  },
  rename_action_keys = {
    quit = "<C-c>",
    exec = "<CR>",
  },
  rename_prompt_populate = true,
  definition_preview_icon = "  ",
  border_style = "single",
  rename_prompt_prefix = "➤",
  server_filetype_map = {},
  diagnostic_prefix_format = "%d. ",
}

saga.config_values.dianostic_header_icon = saga.config_values.diagnostic_header_icon

local extend_config = function(opts)
  opts = opts or {}
  if next(opts) == nil then
    return
  end
  for key, value in pairs(opts) do
    if saga.config_values[key] == nil then
      error(string.format("[LspSaga] Key %s not exist in config values", key))
      return
    end
    if key == "dianostic_header_icon" then
      --- TODO: remove
      print "dianostic_header_icon will be depericated soon due to miss-spelling. use 'diagnostic_header_icon'"
    end
    if type(saga.config_values[key]) == "table" then
      for k, v in pairs(value) do
        saga.config_values[key][k] = v
      end
    else
      saga.config_values[key] = value
    end
  end
end

saga.init_lsp_saga = function(opts)
  extend_config(opts)
  local config = saga.config_values

  if config.use_saga_diagnostic_sign then
    for type, icon in pairs {
      Error = config.error_sign,
      Warn = config.warn_sign,
      Hint = config.hint_sign,
      Info = config.infor_sign,
    } do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, {
        text = icon,
        texthl = hl,
        numhl = "",
      })
    end
  end

  if config.code_action_prompt.enable then
    require("lspsaga.codeaction.indicator").attach()
  end
end

saga.setup = saga.init_lsp_saga

return saga
