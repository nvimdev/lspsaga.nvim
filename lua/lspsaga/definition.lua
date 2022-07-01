local libs,window = require('lspsaga.libs'),require('lspsaga.window')
local home_dir = libs.get_home_dir()
local config = require('lspsaga').config_values
local lsp,fn,api = vim.lsp,vim.fn,vim.api
local scroll_in_win = require('lspsaga.action').scroll_in_win
local def = {}
local saga_augroup = require('lspsaga').saga_augroup

function def.preview_definition(timeout_ms)
  if not libs.check_lsp_active() then
    return
  end

  local filetype = vim.api.nvim_buf_get_option(0, "filetype")

  local method = "textDocument/definition"
  local params = lsp.util.make_position_params()
  local result = vim.lsp.buf_request_sync(0,method,params,timeout_ms or 1000)
  if result == nil or vim.tbl_isempty(result) then
    vim.notify("No location found: " .. method)
    return nil
  end
  result = vim.tbl_values(result)

  if vim.tbl_islist(result) and not vim.tbl_isempty(result[1]) then
    if result[1].result[1] == nil or vim.tbl_isempty(result[1].result[1]) then
      print('No definitions found')
      return
    end
    local uri = result[1].result[1].uri or result[1].result[1].targetUri
    if #uri == 0 then return end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri)
    local short_name
    local root_dir = libs.get_lsp_root_dir()

    -- reduce filename length by root_dir or home dir
    if link:find(root_dir, 1, true) then
      short_name = link:sub(root_dir:len() + 2)
    elseif link:find(home_dir, 1, true) then
      short_name = link:sub(home_dir:len() + 2)
      -- some definition still has a too long path prefix
      if #short_name > 40 then
        short_name = libs.split_by_pathsep(short_name,4)
      end
    else
      short_name = libs.split_by_pathsep(link,4)
    end

    if not vim.api.nvim_buf_is_loaded(bufnr) then
        fn.bufload(bufnr)
    end
    local range = result[1].result[1].targetRange or result[1].result[1].range
    local start_line = 0
    if range.start.line - 3 >= 1 then
      start_line = range.start.line - 3
    else
      start_line = range.start.line
    end

    local content =
        vim.api.nvim_buf_get_lines(bufnr, start_line, range["end"].line + 1 +
        config.max_preview_lines, false)
    content = vim.list_extend({config.definition_preview_icon.."Definition Preview: "..short_name,"" },content)

    local opts = {
      relative = "cursor",
      style = "minimal",
    }
    local WIN_WIDTH = api.nvim_get_option('columns')
    local max_width = math.floor(WIN_WIDTH * 0.5)
    local width, _ = vim.lsp.util._make_floating_popup_size(content, opts)

    if width > max_width then
      opts.width = max_width
    end

    local content_opts = {
      contents = content,
      filetype = filetype,
      highlight = 'LspSagaDefPreviewBorder'
    }

    local bf,wi = window.create_win_with_border(content_opts,opts)

    local current_buf = api.nvim_get_current_buf()
    api.nvim_create_autocmd({"CursorMoved", "CursorMovedI","BufHidden", "BufLeave"},{
      group = saga_augroup,
      buffer = current_buf,
      once = true,
      callback = function()
        if api.nvim_win_is_valid(wi) then
          api.nvim_win_close(wi,true)
        end
      end
    })
    vim.api.nvim_buf_add_highlight(bf,-1,"DefinitionPreviewTitle",0,0,-1)

    api.nvim_buf_set_var(0,'lspsaga_def_preview',{wi,1,config.max_preview_lines,10})
  end
end

function def.has_saga_def_preview()
  local has_preview,pdata = pcall(api.nvim_buf_get_var,0,'lspsaga_def_preview')
  if has_preview and api.nvim_win_is_valid(pdata[1]) then return true end
  return false
end

function def.scroll_in_def_preview(direction)
  local has_preview,pdata = pcall(api.nvim_buf_get_var,0,'lspsaga_def_preview')
  if not has_preview then return end
  local current_win_lnum = scroll_in_win(pdata[1],direction,pdata[2],config.max_preview_lines,pdata[4])
  api.nvim_buf_set_var(0,'lspsaga_def_preview',{pdata[1],current_win_lnum,config.max_preview_lines,pdata[4]})
end

return def
