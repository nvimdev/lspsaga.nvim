## Default Options

default options in `rename` section.

- `in_select = true`          defualt is true when open rename window is select mode
- `auto_save = true`          auto save file when rename done
- `project_max_width = 0.5`   set project_replace float window width
- `project_max_height = 0.5`  set project_replace Float window height

## Default keymaps

default keymap in `rename.keys` section.

- `quit = '<Esc>'`             quit rename window or project_replace window
- `exec = '<CR>'`              execute rename in rename window or execute replace in project_replace window
- `select = 'x'`               select or cancel select item in project_replace float window


## Rename Usage

command is `:Lspsaga lsp_rename`. when open rename window it will also highlight the references in this buffer.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/bb81149a-d24e-4f14-a8b5-ddf0cc1d9908)

### Change start mode from command

In some situation like just want change one or less characters. `in_select` will cause a trouble. Now you can pass
mode from command like `:Lspsaga lsp_rename mode=n`.

## Project Replace

lsp rename only can rename language file in doc or some other places lsp not handle that. Lspsaga provide async project
level search and replace by using `rg`. make sure you install `rg`.  

Command is `:Lspsaga project_replace old_name new_name`. It will search whole project to find old_name. and popup
flaot window.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/5afdbf13-f88a-4adc-8f79-5fd48da61743)

- use `rename.keys.select` to select item to rename
- use `rename.keys.exec` to execute new_name replace.

### Integration lsp rename

use `++project` flag on command `:Lspsaga lsp_rename ++project` after lsp rename done . if project still have this name usage it will popup project_replace.