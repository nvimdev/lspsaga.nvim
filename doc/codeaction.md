## Code Action Usage

command is `:Lspsaga code_action`

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/5327de84-9239-451d-89d2-3dd5a9585c06)

suggest workflow

- if you know the action do just press the action number
- if you don't know what the action do move to it see action preview then press `CR`

## Default Options

default options in `code_action` section.

- `num_shortcut = true`        support number shutcut execute action when code action window show
- `show_server_name = false`   show language server name
- `extend_gitsigns = false`    extend gitsigns plugin diff action

## Default keymaps

defualt keymap in `code_action.keys` section.

- `quit = 'q'`    quit the float window
- `exec = '<CR>'` execuate action

## Different with neovim code action

neovim builtin codeaction use line diagnostic to request code action. lspsaga just use cursor diagnostic. this will reduce some actions of other place in line which you don't need . 