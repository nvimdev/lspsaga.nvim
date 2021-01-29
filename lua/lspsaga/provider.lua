local window = require 'lspsaga.window'
local vim,api,lsp,vfn = vim,vim.api,vim.lsp,vim.fn
local root_dir = lsp.buf_get_clients()[1].config.root_dir or ''
local wrap = require('lspsaga.wrap')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')

local send_request = function(timeout)
  local method = {"textDocument/definition","textDocument/references"}
  local def_params = lsp.util.make_position_params()
  local ref_params = lsp.util.make_position_params()
  ref_params.context = {includeDeclaration = true;}
  local def_response = lsp.buf_request_sync(0, method[1], def_params, timeout or 1000)
  local ref_response = lsp.buf_request_sync(0, method[2], ref_params, timeout or 1000)

  local responses = {}
  if not vim.tbl_isempty(def_response) then
    table.insert(responses,def_response)
  end
  if not vim.tbl_isempty(ref_response) then
    table.insert(responses,ref_response)
  end

  for i,response in ipairs(responses) do
    if type(response) == "table" then
      for _,res in pairs(response) do
        if res.result and next(res.result) ~= nil then
          coroutine.yield(res.result,i)
        end
      end
    end
  end
end

local Finder = {}

function Finder:lsp_finder_request()
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end
  self.WIN_WIDTH = vim.fn.winwidth(0)
  self.WIN_HEIGHT = vim.fn.winheight(0)
  self.contents = {}
  self.short_link = {}

  local request_intance = coroutine.create(send_request)
  self.buf_filetype = api.nvim_buf_get_option(0,'filetype')
  while true do
    local _,result,method_type = coroutine.resume(request_intance)
    self:create_finder_contents(result,method_type)

    if coroutine.status(request_intance) == 'dead' then
      break
    end
  end
  self:render_finder_result()
end

function Finder:create_finder_contents(result,method_type)
  local target_lnum = 0
  if type(result) == 'table' then
    local method_option = {
      {icon = config.finder_definition_icon,title = ':  '.. #result ..' Definitions'};
      {icon = config.finder_reference_icon,title = ':  '.. #result ..' References',};
    }
    local params = vim.fn.expand("<cword>")
    self.param_length = #params
    local title = method_option[method_type].icon.. params ..method_option[method_type].title

    if method_type == 1 then
      table.insert(self.contents,title)
      target_lnum = 2
    else
      target_lnum = target_lnum + self.definition_uri + 5
      table.insert(self.contents," ")
      table.insert(self.contents,title)
    end

    if method_type == 1 then
      self.definition_uri = #result
    else
      self.reference_uri  = #result
    end

    for index,_ in ipairs(result) do
      local uri = result[index].targetUri or result[index].uri
      if uri == nil then
          return
      end
      local bufnr = vim.uri_to_bufnr(uri)
      if not api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
      end
      local link = vim.uri_to_fname(uri)
      local short_name

      -- reduce filename length by root_dir or home dir
      if link:find(root_dir, 1, true) then
        short_name = link:sub(root_dir:len() + 2)
      elseif link:find(libs.home, 1, true) then
        short_name = link:sub(libs.home:len() + 2)
      else
        short_name = libs.split_by_pathsep(link,4)
      end

      local target_line = '['..index..']'..' '..short_name
      local range = result[index].targetRange or result[index].range
      if index == 1  then
        table.insert(self.contents,' ')
      end
      table.insert(self.contents,target_line)
      target_lnum = target_lnum + 1
      local lines = api.nvim_buf_get_lines(bufnr,range.start.line-0,range["end"].line+1+5,false)

      self.short_link[target_lnum] = {
        link=link,
        preview=lines,
        row=range.start.line+1,
        col=range.start.character+1
      }
    end
  end
end

function Finder:render_finder_result()
  if next(self.contents) == nil then return end

  table.insert(self.contents,' ')

  local help = {
    "[o] : Open File     [s] : Vsplit";
    "[i]   : Split       [q] : Exit";
  }

  local max_idx= 1
  for i=1,#self.contents-1,1 do
    if #self.contents[i] > #self.contents[max_idx] then
      max_idx = i
    end
  end

  local truncate_line
  if #self.contents[max_idx] > #help[1] then
    truncate_line = wrap.add_truncate_line(self.contents)
  else
    truncate_line = wrap.add_truncate_line(help)
  end

  table.insert(self.contents,truncate_line)

  for _,v in ipairs(help) do
    table.insert(self.contents,v)
  end

  -- get dimensions
  local width = api.nvim_get_option("columns")
  local height = api.nvim_get_option("lines")

  -- calculate our floating window size
  local win_height = math.ceil(height * 0.8)
  local win_width = math.ceil(width * 0.8)

  -- and its starting position
  local row = math.ceil((height - win_height) * 0.7)
  local col = math.ceil((width - win_width))
  local opts = {
    style = "minimal",
    relative = "editor",
    row = row,
    col = col,
  }

  local border_opts = {
    border = config.border_style,
    highlight = 'LspSagaLspFinderBorder'
  }
  self.contents_buf,self.contents_win,self.border_bufnr,self.border_win = window.create_float_window(self.contents,'plaintext',border_opts,true,opts)
  api.nvim_buf_set_option(self.contents_buf,'buflisted',false)
  api.nvim_win_set_var(self.conents_win,'lsp_finder_win_opts',opts)
  api.nvim_win_set_option(self.conents_win,'cursorline',true)

  if not self.cursor_line_bg and not self.cursor_line_fg then
    self:get_cursorline_highlight()
  end
  api.nvim_command('hi CursorLine guifg='..config.selected_fg .. ' guibg='..config.selected_bg)
--   api.nvim_win_set_cursor(M.contens_buf,{2,1})
  api.nvim_command('autocmd CursorMoved <buffer> lua require("lspsaga.provider").set_cursor()')
  api.nvim_command('autocmd CursorMoved <buffer> lua require("lspsaga.provider").auto_open_preview()')
  api.nvim_command("autocmd QuitPre <buffer> lua require('lspsaga.provider').close_lsp_finder_window()")

  for i=1,self.definition_uri,1 do
    api.nvim_buf_add_highlight(self.contents_buf,-1,"TargetFileName",1+i,0,-1)
  end

  for i=1,self.reference_uri,1 do
    api.nvim_buf_add_highlight(self.contents_buf,-1,"TargetFileName",i+self.definition_uri+4,0,-1)
  end
  -- load float window map
  self:apply_float_map()
  self:lsp_finder_highlight()
end

function Finder:apply_float_map()
  local nvim_create_keymap = require('lspsaga.libs').nvim_create_keymap
  local lhs = {
    noremap = true,
    silent = true
  }
  local keymaps = {
    {self.contents_bufnr,'n',"o",":lua require'lspsaga.provider'.open_link(1)<CR>"},
    {self.contents_bufnr,'n',"s",":lua require'lspsaga.provider'.open_link(2)<CR>"},
    {self.contents_bufnr,'n',"i",":lua require'lspsaga.provider'.open_link(3)<CR>"},
    {self.contents_bufnr,'n',"q",":lua require'lspsaga.provider'.close_lsp_finder_window()<CR>"}
  }
  nvim_create_keymap(keymaps,lhs)
end

function Finder:lsp_finder_highlight ()
  local def_icon = config.finder_definition_icon or ''
  local ref_icon = config.finder_reference_icon or ''
  local def_uri_count = self.definition_uri
  local ref_uri_count = self.reference_uri
  -- add syntax
  api.nvim_buf_add_highlight(self.contents_buf,-1,"DefinitionIcon",0,1,#def_icon-1)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"TargetWord",0,#def_icon,self.param_length+#def_icon+3)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"DefinitionCount",0,0,-1)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"TargetWord",3+def_uri_count,#ref_icon,self.param_length+#ref_icon+3)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"ReferencesIcon",3+def_uri_count,1,#ref_icon+4)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"ReferencesCount",3+def_uri_count,0,-1)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"ProviderTruncateLine",def_uri_count+ref_uri_count+6,0,-1)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"HelpItem",def_uri_count+ref_uri_count+7,0,-1)
  api.nvim_buf_add_highlight(self.contents_buf,-1,"HelpItem",def_uri_count+ref_uri_count+8,0,-1)
end

function Finder:set_cursor()
  local current_line = vim.fn.line('.')
  local column = 2

  local first_def_uri_lnum = 3
  local last_def_uri_lnum = 3 + self.definition_uri - 1
  local first_ref_uri_lnum = 3 + self.definition_uri + 3
  local last_ref_uri_lnum = 3 + self.definition_uri + 2 + self.reference_uri

  if current_line == 1 then
    vim.fn.cursor(first_def_uri_lnum,column)
  elseif current_line == last_def_uri_lnum + 1 then
    vim.fn.cursor(first_ref_uri_lnum,column)
  elseif current_line == last_ref_uri_lnum + 1 then
    vim.fn.cursor(first_def_uri_lnum, column)
  elseif current_line == first_ref_uri_lnum - 1 then
    vim.fn.cursor(last_def_uri_lnum,column)
  elseif current_line == first_def_uri_lnum - 1 then
    vim.fn.cursor(last_ref_uri_lnum,column)
  end
end

function Finder:get_cursorline_highlight()
  self.cursor_line_bg = vfn.synIDattr(vfn.hlID("cursorline"),"bg")
  self.cursor_line_fg = vfn.synIDattr(vfn.hlID("cursorline"),"fg")
end

function Finder:auto_open_preview()
  local current_line = vim.fn.line('.')
  if not self.short_link[current_line] then return end
  local content = self.short_link[current_line].preview or {}

  if next(content) ~= nil then
    local has_var,finder_win_opts = pcall(api.nvim_win_get_var,0,'lsp_finder_win_opts')
    if not has_var then print('get finder window options wrong') return end
    local width = vim.fn.winwidth(0)
    local height = vim.fn.winheight(0)
    local opts = {
      relative = 'win',
    }

    local min_width = 45
    local pad_right = self.WIN_WIDTH - width - 20 - min_width

    opts.width = min_width
    if pad_right > 5 then
      opts.col = finder_win_opts.col+width+2
      opts.row = finder_win_opts.row
    elseif pad_right < 0 then
      opts.row = finder_win_opts.row + height + 2
      opts.col = finder_win_opts.col
      if self.WIN_HEIGHT - height - opts.row - #content + 6 < 2 then
        return
      end
    end

    local border_opts = {
      border = config.border_style,
      highlight = 'LspSagaAutoPreview'
    }
    vim.defer_fn(function ()
      self:close_auto_preview_win()
      local cb,cw,_,bw = window.create_float_window(content,self.buf_filetype,border_opts,false,opts)
      api.nvim_buf_set_option(cb,'buflisted',false)
      api.nvim_win_set_var(0,'saga_finder_preview',{cw,bw})
    end,10)
  end
end

function Finder:close_auto_preview_win()
  local has_var,winid = pcall(api.nvim_win_get_var,0,'saga_finder_preview')
  if has_var then
    window.nvim_close_valid_window(winid)
  end
end

-- action 1 mean enter
-- action 2 mean vsplit
-- action 3 mean split
function Finder:open_link(action_type)
  local action = {"edit ","vsplit ","split "}
  local current_line = vim.fn.line('.')

  if self.short_link[current_line] == nil then
    error('[LspSaga] target file uri not exist')
    return
  end

  self:close_auto_preview_win()
  api.nvim_win_close(self.contents_win,true)
  api.nvim_win_close(self.border_win,true)
  api.nvim_command(action[action_type]..self.short_link[current_line].link)
  vim.fn.cursor(self.short_link[current_line].row,self.short_link[current_line].col)
  self:clear_tmp_data()
end

function Finder:quit_float_window()
  self:close_auto_preview_win()
  if self.contents_win ~= 0 and self.border_win ~= 0 then
    window.nvim_close_valid_window(self.contents_win)
    window.nvim_close_valid_window(self.border_win)
  end
  self:clear_tmp_data()
end

function Finder:clear_tmp_data()
  self.short_link = {}
  self.contents = {}
  self.definition_uri = 0
  self.reference_uri = 0
  self.param_length = 0
  self.buf_filetype = ''
  self.WIN_HEIGHT = 0
  self.WIN_WIDTH = 0
  api.nvim_command('hi! CursorLine  guibg='..self.cursor_line_bg)
  if self.cursor_line_fg == '' then
    api.nvim_command('hi! CursorLine  guifg=NONE')
  end
end

local lspfinder = {}

function lspfinder.lsp_finder()
  Finder:lsp_finder_request()
end

function lspfinder.close_lsp_finder_window()
  Finder:quit_float_window()
end

function lspfinder:auto_open_preview()
  Finder:auto_open_preview()
end

function lspfinder:set_cursor()
  Finder:set_cursor()
end

function lspfinder.open_link(action_type)
  Finder:open_link(action_type)
end

function lspfinder.preview_definition(timeout_ms)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  local method = "textDocument/definition"
  local params = lsp.util.make_position_params()
  local result = vim.lsp.buf_request_sync(0,method,params,timeout_ms or 1000)
  if result == nil or vim.tbl_isempty(result) then
      print("No location found: " .. method)
      return nil
  end
  if vim.tbl_islist(result) and not vim.tbl_isempty(result[1]) then
    local uri = result[1].result[1].uri or {}
    if #uri == 0 then return end
    local bufnr = vim.uri_to_bufnr(uri)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
    end
    local range = result[1].result[1].targetRange or result[1].result[1].range
    local content =
        vim.api.nvim_buf_get_lines(bufnr, range.start.line, range["end"].line + 1 +
        10, false)
    content = vim.list_extend({config.definition_preview_icon.."Definition Preview",""},content)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    local opts = {
      relative = "cursor",
      style = "minimal",
    }
    local border_opts = {
      border = config.border_style,
      highlight = 'LspSagaDefPreviewBorder'
    }
    local contents_buf,contents_winid,_,border_winid = window.create_float_window(content,filetype,border_opts,false,opts)
    vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"},
                                        border_winid)
    vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"},
                                        contents_winid)
    vim.api.nvim_buf_add_highlight(contents_buf,-1,"DefinitionPreviewTitle",0,0,-1)
  end
end

return lspfinder
