## Version 0.2.2 -- 2022--09-09

- fix symbolwinbar high memory usage
- `preview_definition` chang to `peek_definition` support edit definition file in floatwindow and highlight
- `code_action` support in visual mode .
- `finder` preview highlight current word.
-  show diagnostic source by default.
- add lspsaga codeaction keymap in diagnostic header

## Remove

-  remove `definition_preview_icon`  option
- remove `finder_preview_hl_ns`
- remove `diagnostic_source_bracket`
- remove `show_diagnostic_source` . 

## Version 0.2.1 -- 2022-08-30

### New

- improve scroll in preview remove old implement of preview
- add new option  `scroll_in_preview` use default scroll keymap to scroll `hover` `finder preview`
- use `CursorMoved` with timer in LightBulb instead of using `CursorHold` `CursorHoldI`
- new option `update_time` in code_action_lightbulb
- auto jump into the `preview_definition` window
- `floaterm` can save the state.

### Bug fix

- fix `definition_preview` and `hover` window not closed when `CursorMoved`
- fix `finder` works not well when server has multiple servers

### Remove

- remove function `action.smart_scroll_with_saga(1)` no need this function

## Version 0.2

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
