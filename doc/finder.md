### What's New?

The new finder is no longer called lsp_finder. It is much more powerful. Better scalability. Better window layout. More stable.

### Default Options

these are defeault options in `finder` section.

- `max_height = 0.5`        max_height of finder layout window
- `left_width = 0.3`        finder layout left window width-
- `default = 'ref+imp'`     default methods show in finder ref mean `references` imp mean `implementation` they are alias 
- `methods = {}`            key is alias of lsp methods value is lsp methods which you want show in finder.
- `layout = 'float'`        available value is `normal` or `float` normal will use normal layout window priority is lower than command layout
- `filter = {}`             key is lsp method value is a filter handler function parameter are `client_id` `result`

### Default KeyMap

these are defaule keymaps in `finder.keys` table section.

- `shuttle = '[w'`       shuttle bettween the finder layout window
- `toggle_or_open = 'o'` toggle expand or open
- `vsplit = 's'`         open in vsplit
- `split = 'i'`          open in split
- `tabe = 't'`           open in tabe
- `tabnew = 'r'`         open in new tab
- `quit = 'q'`           quit the finder only work in layout left window
- `close = '<C-c>k'`     close finder

### How to change options

put the option which you want change in `setup` function parameter table. like

```lua
require('lspsaga').setup({
  finder = {
    max_height = 0.6
    keys = {
      vsplit = 'v'
    }
  }
})
```

### Finder Usage

basiclly usage is `:Lspsaga finder` then you will see the finder layout window . It will show you the `references` and `implemnetation` results. relate options is `default = 'ref+imp'` (see above)

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/1d957dda-5825-4d15-8d5a-ca5dd7ca63a9)

#### Change Lsp Methods in finder

There has two ways, First is from command this way has a high priority if you pass methods alais from command it will ignore `default` options. like `:Lspsaga finder imp` this will only show `implementation` or like `:Lspsaga finder def+ref` this will only show `definition` and `references` . like `:Lspsaga finder def+ref`.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/27541a92-9691-4df3-8d18-c4b88ec4ce5e)

Second is change `default` option like `default = 'def+ref+imp'` it will show `definition` `references` `implementation`.

You can use single alias or combine alias in `finder`. these are both correct.

```
:Lspsaga finder ref      same as default = 'ref'
:Lspsaga finder def+ref  same as default = 'def+ref'
```

and more with your custom `methods`. **This is the extensibility of finder now.**

**How can i add new methods which i want show in finder ?**

That's easy, config register the method to `methods` option table. key is method alias that you can use in command or `default` option. value is lsp method usually is `textDocument/foo` . example I want finder show `textDocument/typeDefinition`in finder need do like this.

```lua
require('lspsaga').setup({
  finder = {
    methods = {
      'tyd' = 'textDocument/typeDefinition'
    }
  }
})
```

then you can do `:Lspsaga finder tyd` or combine other methods `:Lspsaga finder tyd+ref+def`  or use in `default = 'typd+ref`
example the image is `:Lspsaga finder tyd+ref+imp+def` same as `default ='tyd+ref+imp+def'`

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/fcf2bb52-288f-480d-9c9e-342b4f450da7)


in default finder registered three mehtods which is `def` is `textDocument/definition` `ref` is `textDocument/references` `imp` is `textDocuemnt/implementation` . Then you can combine these aliases as you like. Example

```lua
```

Notice current indent highlight is  provider by `finder` not provide by any third-party plugin. it will disappear when you jump to other window. if you see the indent line provide by other indent plugin please consider add `sagafinder` filetype to that plugin exclude list.

![Untitled](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/009990db-5ba5-455b-ab3f-d9bd25904cf0)


#### Change Finder Layout

same as finder show lsp methods . you can use command and option to config it . if you don't pass any layout from command it will use `layout` option. available value is `normal ` and `layout` . a little different is when you want change layout from command you need `++` before the layout like `:Lspsaga finder ++normal`.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/df566e6f-fd45-47c2-a34e-b70ab248f400)