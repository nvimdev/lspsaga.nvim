if exists('g:loaded_lspsaga') | finish | endif

let s:save_cpo = &cpo
set cpo&vim

if !has('nvim')
    echohl Error
    echom "Sorry this plugin only works with versions of neovim that support lua"
    echohl clear
    finish
endif

let g:loaded_lspsaga = 1

let s:bg_color = synIDattr(hlID("Normal"), "bg")

highlight default LspSagaFinderSelection guifg=#89d957 guibg=NONE gui=bold

highlight default LspFloatWinBorder guifg=black guibg=NONE
highlight default LspSagaBorderTitle guifg=orange guibg=NONE gui=bold

highlight default link LspFloatWinNormal Normal
highlight default link TargetWord Error
highlight default link ReferencesCount Title
highlight default link DefinitionCount Title
highlight default link TargetFileName  Comment
highlight default link DefinitionIcon Special
highlight default link ReferencesIcon Special
highlight default ProviderTruncateLine guifg=black guibg=NONE
highlight default SagaShadow guibg=#000000

highlight default LspSagaFinderSelection guifg=#89d957 guibg=NONE gui=bold

highlight default link DefinitionPreviewTitle Title

highlight default LspSagaDiagnosticBorder guifg=#7739e3 guibg=NONE
highlight default DiagnosticHeader guifg=#d8a657 guibg=NONE gui=bold
highlight default LspSagaDiagnosticTruncateLine guifg=black guibg=NONE

highlight default link LspSagaDiagnosticError DiagnosticError
highlight default link LspSagaDiagnosticWarn DiagnosticWarn
highlight default link LspSagaDiagnosticInfo DiagnosticInfo
highlight default link LspSagaDiagnosticHint DiagnosticHint

highlight default LspSagaShTruncateLine guifg=black guibg=NONE
highlight default LspSagaDocTruncateLine guifg=black guibg=NONE

highlight default LspSagaTruncateLine guifg=black guibg=NONE

highlight default LspSagaCodeActionTitle guifg=#da8548 gui=bold
highlight default LspSagaCodeActionBorder guifg=#98be65
highlight default LspSagaCodeActionContent guifg=#98be65 gui=bold

highlight default LspSagaRenamePromptPrefix guifg=#98be65 guibg=NONE

highlight default LspSagaRenameBorder guifg=#3bb6c4
highlight default LspSagaHoverBorder guifg=#80A0C2 guibg=NONE
highlight default LspSagaSignatureHelpBorder guifg=#98be65 guibg=NONE

highlight default LspSagaLspFinderBorder guifg=#51afef guibg=NONE
highlight default LspSagaAutoPreview guifg=#ECBE7B guibg=NONE
highlight default LspSagaDefPreviewBorder guifg=#b3deef guibg=NONE

highlight default link LspSagaLightBulb LspDiagnosticsSignHint

function! s:lspsaga_complete(...)
  return join(luaeval('require("lspsaga.command").command_list()'),"\n")
endfunction

" LspSaga Commands with complete
command! -nargs=+ -complete=custom,s:lspsaga_complete Lspsaga    lua require('lspsaga.command').load_command(<f-args>)

let &cpo = s:save_cpo
unlet s:save_cpo
