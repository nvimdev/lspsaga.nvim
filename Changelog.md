## Version 2

### BreakChange

Please use command in `vim.keymap.set` rhs . check the README.

### New

- `Finder:` support show `implement` in `Lspsaga lsp_finder`
- `Finder:` add option `imp` in `finder_icons`
- `LightBulb` add api to genreate sign need neovim 0.8 nightly. 0.7 version also use `vim.fn.sign_place/unplace`
-  `LightBulb` set the `CursorHold CursorHoldI` only take effect when the buffer has lsp server. and remove them when 
    buffer delete ,keep the autocmds clean
- `Background of Lspsaga floatwindow` now it will use the colorscheme Normal highlight
- `Notify` add notify for some commands if there has no server give a message
-  `Symbolwinbar` when delete the buffer remove the buffer events that symbolwinbar used,keep autocmds clean
-  `Outline` remove the patch as [neovim#19458](https://github.com/neovim/neovim/issues/19458#)completed
-  `Outline` fix bug
-  `Definition` rewrite definition
-  Close the `finder` `rename` window when use wincmd shortcut jump to other window like `<C-w>h`
-  `Diagnostic` fix the virtual text bug when jump diagnostic
-   Better `show_line_diagnostic` and `show_cursor_diagnostic`
-  `custom_kind` option change the default lspkind icon and color

### Remove

- remove `Lspsaga implement`.
