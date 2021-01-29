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

command! -range -bar LspSagaFinder lua require("lspsaga.provider").lsp_finder()
command! -range -bar LspSagaDefPreview lua require("lspsaga.provider").preview_definition()
command! -range -bar LspSagaRename lua require("lspsaga.rename").rename()
command! -range -bar LspSagaHoverDoc lua require("lspsaga.hover").render_hover_doc()
command! -range -bar LspSagaShowLineDiags lua require("lspsaga.diagnostic").show_line_diagnostics()
command! -range -bar LspSagaDiagJumpNext lua require("lspsaga.diagnostic").lsp_jump_diagnostic_next()
command! -range -bar LspSagaDiagJumpPrev lua require("lspsaga.diagnostic").lsp_jump_diagnostic_prev()
command! -range -bar LspSagaCodeAction lua require("lspsaga.codeaction").code_action()
command! -range -bar LspSagaRangeCodeAction lua require("lspsaga.codeaction").range_code_action()
command! -range -bar LspSagaOpenFloaterm lua require("lspsaga.floaterm").open_float_terminal()
command! -range -bar LspSagaCloseFloaterm lua require("lspsaga.floaterm").close_float_terminal()

highlight default LspSagaFinderSelection guifg='#1c1f24' guibg='#b3deef'

let &cpo = s:save_cpo
unlet s:save_cpo
