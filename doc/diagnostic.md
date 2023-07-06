## Default Options

default options of diagnostic module. 

- `show_code_action = true`          show code action in diagnostic jump window very useful suggest true.
- `jump_num_shortcut = true`         when use diangostic jump enable number keymap to execute code action fast
- `max_width = 0.8`                  diagnostic jump window max width
- `max_height = 0.6`                 diagnostic jump window max height
- `text_hl_follow = true`           diagnsotic jump window text highlight follow diagnostic type
- `border_follow = true `           diagnostic jump window border follow diagnsotic type
- `extend_relatedInformation = false` when have relatedInormation extend to diagnostic message
- `show_layout = 'float'`            config layout of diagnostic show window not jumo window.
- `show_normal_height = 10`          show window height when diagnostic show window layout is normal
- `max_show_width = 0.9`            show window max width when layout is float
- `max_show_height = 0.6`           show window max height when layout is float
- `diagnostic_only_current = false`  only show diagnostic virtual text on current line.

## Default Keymap

these are default keymap config in `diagnostic.keys` section

- `exec_action = 'o' `              executate action when in jump window
- `quit = 'q' `                     quit diagnostic jump window when in jump window
- `toggle_or_jump = '<CR>'`         toggle or jump to position when in diagnsotic show window
- `quit_in_show = { 'q', '<ESC>' }` quit diagnostic show window

### Example to change default options or keymap in setup

```lua
require('lspsaga').setup({
    diagnostic = {
        max_height = 0.8,
        keys = {
            quit = {'q', '<ESC>'}
        }
    },
})
```

## Diagnostic Jump Usage

you need config a keymap for command `:Lspsaga diangostic_jump_next` and `:Lspsaga diagnsotic_jump_prev`.
When cursor position have diagnostic it will show in current not go prev or next position.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/d88f9d9f-fae1-47ca-94d2-8ef536e4eb7f)

when diagnostic window rendered. you can use `scroll_preview` to preview code action. default is `<C-f>` and `<C-b>`.

![Untitled](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/91d9c0a0-ee1e-4f70-9d6b-08e32fad8b98)

workflow in gif need `jump_num_shutcut` true.

1. set `[e`  to jump next diangostic `vim.keymap.set('n', '[e', '<cmd>Lspsaga diagnsotic_jump_next)`
2. current position has diagnsotic so not jump to other place.
3. use `<C-f>` and `<C-b>` scroll in code action section to preview code action.
4. press num key `2` to execute code action `2`.

In some situation like copy the diagnostic message text want jump to diagnsotic jump window. you can use `<C-w>w` wincmd to jump. and use `keys.quit` to quit the window or move to code action then press `o` to execute code action.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/ac085c8e-dd6b-4995-8201-c474966abb61)

### Diagnsotic jump Filter

if you want only jump to error or some other severity diagnostic .you can use function to config like.

```lua
keymap("n", "[E", function()
  require("lspsaga.diagnostic"):goto_prev({ severity = vim.diagnostic.severity.ERROR })
end)
```

## Diagnostic Show

Lspsaga support show `cursor` `line` `buffer` `workspace` diangostics in a float window or normal window. 

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/e8e2e3cd-715b-41d4-a526-aa934fe10a80)

you can use the `keys.toggle_or_jump` to expand or collapse some file or jump to the diangostic position.

### How to change the layout of diagnostic window

support from command or option `show_layout` to change it , if you pass layout from command it will ignore default option.
`:Lspsaga show_workspace_diagnsotics ++normal/++float`

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/4ab7dba7-58d3-4d5f-9af9-bba7fd61db95)

### Unfocus the diangsotic show float window.

when command has `:Lspsaga show_buf_diagnostics ++unfocus` . the cursor will not jump to the diangostic show window. and show window will auto delete when these autocmd events triggered `'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufDelete', 'WinScrolled'`


## Diagnostic  only current line

when you enable default neovim diagnostic virtual text it will all diagnsotics virtual text. you can set `diagnostic_only_current = true` to show the diangostic virtual text only in current line.

notice you need disable default neovim diagnostic virtual text by using

```lua
vim.diagnostic.config({
    virtual_text = false
})
```

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/2a40e1cc-908d-4576-a32d-afcb27800101)