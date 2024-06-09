---@class LspsagaConfig
---@field public ui? LspsagaConfig.Ui Global UI config
---@field public hover? LspsagaConfig.Hover Hover documentation
---@field public diagnostic? LspsagaConfig.Diagnostic LSP Diagnostic popup
---@field public code_action? LspsagaConfig.CodeAction LSP Code Action popup
---@field public lightbulb? LspsagaConfig.Lightbulb LSP Lightbulb indicator
---@field public scroll_preview? LspsagaConfig.Scroll.Keys Keys to scroll
---@field public request_timeout? integer LSP request timeout
---@field public finder? LspsagaConfig.Finder Token/reference finder
---@field public definition? LspsagaConfig.Definition Definition
---@field public rename? LspsagaConfig.Rename Rename
---@field public symbol_in_winbar? LspsagaConfig.Crumbs Breadcrumbs
---@field public outline? LspsagaConfig.Outline Outline
---@field public callhierarchy? LspsagaConfig.Hierarchy Call hierarchy
---@field public typehierarchy? LspsagaConfig.Hierarchy Type hierarchy
---@field public implement? LspsagaConfig.Implement Implementation
---@field public beacon? LspsagaConfig.Beacon Beacon
---@field public floaterm? LspsagaConfig.Term Floating terminal

---@class LspsagaConfig.Definition
---@field width? number defines float window width
---@field height? number defines float window height
---@field save_pos? boolean Saves cursor position
---@field keys? LspsagaConfig.Definition.Keys

---@class LspsagaConfig.Rename
---@field in_select? boolean
---@field auto_save? boolean
---@field project_max_width? number
---@field project_max_height? number
---@field keys? LspsagaConfig.Rename.Keys

---@class LspsagaConfig.Crumbs
---@field enable? boolean Enable breadcrumbs
---@field separator? string Separator symbol
---@field hide_keyword? boolean when true some symbols like if and for; ignored if treesitter is not installed
---@field ignore_patterns? string[] Filename patterns to ignore
---@field show_file? boolean Show file name before symbols
---@field folder_level? integer Show how many folder layers before the file name
---@field color_mode? boolean mean the symbol name and icon have same color. Otherwise, symbol name is light-white
---@field delay? integer Dynamic render delay

---@class LspsagaConfig.Outline
---@field win_position? "left" | "right" window position
---@field win_width? integer window width
---@field auto_preview? boolean auto preview when cursor moved in outline window
---@field detail? boolean show detail
---@field auto_close? boolean auto close itself when outline window is last window
---@field close_after_jump? boolean close after jump
---@field layout? LayoutOption when is float above options will ignored
---@field max_height? number Max height of outline window
---@field left_width? number Width of left panel
---@field keys? LspsagaConfig.Outline.Keys

---@class LspsagaConfig.Hierarchy
---@field layout? LayoutOption
---@field left_width? number Width of left panel
---@field keys? LspsagaConfig.Hierarchy.Keys

---@class LspsagaConfig.Implement
---@field enable? boolean Enable implementation plugin
---@field sign? boolean show sign in status column
---@field lang? string[] Additional languages that support implementing interfaces
---@field virtual_text? boolean show virtual text at the end of line
---@field priority? integer sign priority

---@class LspsagaConfig.Term
---@field height? number Floating terminal height
---@field width? number Floating terminal width

---@class LspsagaConfig.Ui
---@field border? BorderType Border type, see `:help nvim_open_win`
---@field devicon? boolean Whether to use nvim-web-devicons
---@field foldericon? boolean Show folder icon in breadcrumbs
---@field title? boolean Show title in some float window
---@field expand? string Expand (drop down) icon
---@field collapse? string Collapse (drop down) icon
---@field code_action? string Code Action (lightbulb) icon
---@field lines? string[] Symbols used in virtual text connect
---@field kind? table LSP kind custom table
---@field button? [string, string] Button icon { '', '' }
---@field imp_sign? string Implement icon

---@class LspsagaConfig.Hover
---@field max_width? number Defines float window width
---@field max_height? number Defines float window height
---@field open_link? string Key for opening links
---@field open_cmd? string Cmd for opening links

---@class LspsagaConfig.Diagnostic
---@field show_layout? LayoutOption Config layout of diagnostic window not jump window
---@field show_normal_height? integer Show window height when diagnostic show window layout is normal
---@field jump_num_shortcut? boolean Enable number shortcuts to execute code action quickly
---@field auto_preview? boolean Auto preview result after change
---@field max_width? number Diagnostic jump window max width
---@field max_height? number Diagnostic jump window max height
---@field max_show_width? number Show window max width when layout is float
---@field max_show_height? number Show window max height when layout is float
---@field wrap_long_lines? boolean Wrap long lines
---@field extend_relatedInformation? boolean When have relatedInformation, diagnostic message is extended to show it
---@field diagnostic_only_current? boolean Only show diagnostic virtual text on the current line
---@field keys? LspsagaConfig.Diagnostic.Keys

---@class LspsagaConfig.CodeAction
---@field num_shortcut? boolean Enable number shortcuts to execute code action quickly
---@field show_server_name? boolean show language server name
---@field extend_gitsigns? boolean extend gitsigns plugin diff action
---@field only_in_cursor? boolean only execute code action in current cursor position
---@field max_height? number code action window max height
---@field cursorline? boolean code action window highlight cursor line
---@field keys? LspsagaConfig.CodeAction.Keys

---@class LspsagaConfig.Lightbulb
---@field enable? boolean enable lightbulb
---@field sign? boolean show sign in status column
---@field debounce? integer timer debounce
---@field sign_priority? integer sign priority
---@field virtual_text? boolean show virtual text at the end of line
---@field enable_in_insert? boolean enable virtual text in insert mode

---@class LspsagaConfig.Finder
---@field max_height? number max_height of the finder window (float layout)
---@field left_width? number width of left panel in finder window
---@field methods? LspMethods
---@field default? "ref" | "imp" | "def" | string Default search results shown; **ref**erences; **imp**lementation; **def**inition; any in config.methods
---@field layout? LayoutOption
---@field silent? boolean If it’s true, it will disable show the no response message
---@field filter? string[] Filter search results
---@field fname_sub? function Filename substitution function
---@field sp_inexist? boolean
---@field sp_global? boolean
---@field ly_botright? boolean
---@field keys? LspsagaConfig.Finder.Keys

---@class LspsagaConfig.Beacon
---@field enable? boolean Enable beacon
---@field frequency? integer

---@class LspsagaConfig.Scroll.Keys
---@field scroll_down? SagaKeys
---@field scroll_up? SagaKeys

---@class LspsagaConfig.Diagnostic.Keys
---@field exec_action? SagaKeys execute action (in jump window)
---@field quit? SagaKeys quit key for the jump window
---@field toggle_or_jump? SagaKeys toggle or jump to position when in `diagnostic_show` window
---@field quit_in_show? SagaKeys quit key for the `diagnostic_show` window

---@class LspsagaConfig.CodeAction.Keys
---@field quit? SagaKeys quit the float window
---@field exec? SagaKeys execute action

---@class LspsagaConfig.Finder.Keys
---@field shuttle? SagaKeys shuttle between the finder layout window
---@field toggle_or_open? SagaKeys toggle expand or open
---@field vsplit? SagaKeys open in vsplit
---@field split? SagaKeys open in hsplit
---@field tabe? SagaKeys open in tabe
---@field tabnew? SagaKeys open in new tab
---@field quit? SagaKeys quit the finder; only works in layout left window
---@field close? SagaKeys close the finder

---@class LspsagaConfig.Hierarchy.Keys
---@field edit? SagaKeys
---@field vsplit? SagaKeys open in vsplit
---@field split? SagaKeys open in hsplit
---@field tabe? SagaKeys open in tabe
---@field quit? SagaKeys quit the hierarchy
---@field shuttle? SagaKeys shuttle between the hierarchy
---@field close? SagaKeys close the hierarchy
---@field toggle_or_req? SagaKeys toggle or do request

---@class LspsagaConfig.Outline.Keys
---@field toggle_or_jump? SagaKeys toggle or jump
---@field quit? SagaKeys quit
---@field jump? SagaKeys jump to pos even on expand/collapse node

---@class LspsagaConfig.Definition.Keys
---@field edit? SagaKeys
---@field vsplit? SagaKeys open in vsplit
---@field split? SagaKeys open in hsplit
---@field tabe? SagaKeys open in tabe
---@field quit? SagaKeys quit the definition
---@field close? SagaKeys close the definition

---@class LspsagaConfig.Rename.Keys
---@field quit? SagaKeys quit rename window or `project_replace` window
---@field exec? SagaKeys execute rename in `rename` window or execute replace in `project_replace` window
---@field select? SagaKeys select or cancel select item in `project_replace` float window

---@alias LayoutOption "float" | "normal"
---@alias BorderType "none" | "single" | "double" | "rounded" | "solid" | "shadow" | string[]
---@alias SagaKeys string | string[]

---@class LspMethods
---@field [string] string Keys are alias of LSP methods. Values are LSP methods, which you want to show in finder.
