local M = {}
local api = vim.api

function M.add_highlight()
  api.nvim_command("hi LspFloatWinBorder guifg=black")
  api.nvim_command("hi def link TargetWord Error")
  api.nvim_command("hi def link ReferencesCount Title")
  api.nvim_command("hi def link DefinitionCount Title")
  api.nvim_command("hi def link TargetFileName  Comment")
  api.nvim_command("hi def link DefinitionIcon Special")
  api.nvim_command("hi def link ReferencesIcon Special")
  api.nvim_command("hi def link HelpTitle Comment")
  api.nvim_command("hi def link HelpItem Comment")

  -- diagnostic
  api.nvim_command("hi DiagnosticTruncateLine guifg=#6699cc gui=bold")
  api.nvim_command("hi def link DiagnosticError Error")
  api.nvim_command("hi def link DiagnosticWarning WarningMsg")
  api.nvim_command("hi DiagnosticInformation guifg=#6699cc gui=bold")
  api.nvim_command("hi DiagnosticHint guifg=#56b6c2 gui=bold")

  api.nvim_command("hi def link DefinitionPreviewTitle Title")

  api.nvim_command("hi DiagnosticBufferTitle guifg=#c594c5 gui=bold")
  api.nvim_command("hi DiagnosticFloatError guifg=#EC5f67")
  api.nvim_command("hi DiagnosticFloatWarn guifg=#d8a657")
  api.nvim_command("hi DiagnosticFloatInfo guifg=#6699cc")
  api.nvim_command("hi DiagnosticFloatHint guifg=#56b6c2")
end

return M

