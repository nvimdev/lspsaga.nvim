## Peek Definition/TypeDefinition Usage

command are `:Lspsaga peek_definition` and `:Lspsaga peek_type_definition`  . layout is `drawer` current only has this layout style.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/b4f1b724-7d6a-49cc-9b4b-6c95b49abae7)

## Default Options

default options in `definition` section

- `width = 0.6`   definition float window width
- `height = 0.5`  definition float window height

## Default Keymap

keymap config in `definition.keys` section

- `edit = '<C-c>o'`
- `vsplit = '<C-c>v'`
- `split = '<C-c>i'`
- `tabe = '<C-c>t'`
- `quit = 'q'`
- `close = '<C-c>k'`

### Why keymap not a single character ?

It call `peek_definition` that mean you can do edit and save in drawer window. the buffer is normal buffer. 
avoid keymap conflict so use prefix `<C-c>` . If you make sure you don't do any edit on `peek_definition` window. you can config it use single character. like

```lua
require('lspsaga').setup({
    definition = {
        keys = {
            edit = 'o'
        }
    }
})
```

> maybe support multpile keymap layout is a good way ? like `:Lspsaga peek_definition key_1` ? IDK


## Goto Definition/TypeDefinition usage

command are `:Lspsaga goto_definition` and `:Lspsaga goto_type_definition`. it will jump to the file and range position.