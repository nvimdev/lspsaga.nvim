## Lightbulb usage

if line has code action the lightbulb will show.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/080e8595-1cfa-460b-9573-a3ae6c144282)

## Default Options
  
- `enable = true`        enable
- `sign = true`          sign
- `virtual_text = true`  virtual text
- `debounce = 10`        timer debounce
- `sign_priority = 40`   sign priority


### How to change the sign 

the sign is `ui.code_action`(see misc.md) config it like:

```lua
require('lspsaga').setup({
    ui = {
        code_action = 'your icon'
    }
})
```