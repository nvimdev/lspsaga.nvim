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

highlight default LspSagaFinderSelection guifg=#89d957 guibg=NONE gui=bold

function! s:lspsaga_complete(...)
  return join(luaeval('require("lspsaga.command").command_list()'),"\n")
endfunction

" LspSaga Commands with complete
command! -nargs=+ -complete=custom,s:lspsaga_complete Lspsaga    lua require('lspsaga.command').load_command(<f-args>)

let &cpo = s:save_cpo
unlet s:save_cpo
