# lspsaga.nvim

A light-weight lsp plugin based on neovim built-in lsp with highly performance UI.

## Install

* vim-plug
```vim
Plug 'neovim/nvim-lspconfig'
Plug 'glepnir/lspsaga.nvim'
```

## Usage

```lua
local saga = require 'lspsaga'

local opts = {
  error_sign = 'your sign',
  warn_sign = 'warn sign',
  hint_sign = 'hint sign',
  infor_sign = 'info sign'
}

saga.init_lsp_saga(opts)

-- code action
nnoremap <silent><leader>ca <cmd>lua
require('lspsaga.codeaction').code_action()<CR>

-- show hover doc
nnoremap <silent> K <cmd>lua vim.lsp.buf.hover()<CR>

-- preview definition
nnoremap <silent> gd <cmd>lua require'lspsaga.provider'.preview_definiton()<CR>

-- lsp provider to find the currsor word definition and reference
nnoremap <silent> gh <cmd>lua require'lspsaga.provider'.lsp_finder({definition_icon='  ',reference_icon = '  '})<CR>

-- jump diagnostic
nnoremap <silent> [e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_next()<CR>
nnoremap <silent> ]e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_next()<CR>

-- float terminal also you can pass the cli command in open_float_terminal function
nnoremap <silent> <A-d> <cmd>lua require('lspsaga.floaterm').open_float_terminal()<CR> -- or open_float_terminal('lazygit')<CR>
tnoremap <silent> <A-d> <C-\><C-n>:lua require('lspsaga.floaterm').close_float_terminal()<CR>
```
