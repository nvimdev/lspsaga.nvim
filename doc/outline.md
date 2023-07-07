## Pre require

`symbols_in_winbar.enable = true` if false the outline not work.

## Outline usage

command is `:Lspsaga outline`

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/a6c81350-3282-4e3a-b373-5e6216f1d83f)

## Default Options

default options of `outline` section.
  
- `win_position = 'right'`     window position
- `win_width = 30`             window width
- `auto_preview = true`        auto preview when cursor moved in outline window
- `detail = true`              show detail
- `auto_close = true`          auto close when outline window is last window
- `close_after_jump = true`    close after jump

## Default keymaps

default keymaps in `outline.keys` section.

- `toggle_or_jump = 'o'`       toggle or jump
- `quit = 'q'` .               quit outline window