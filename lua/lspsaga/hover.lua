local api,lsp,util = vim.api,vim.lsp,vim.lsp.util
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local hover = {}

local call_back = function (_,method,result)
    vim.lsp.util.focusable_float(method, function()
        if not (result and result.contents) then return end
        local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)
        markdown_lines = lsp.util.trim_empty_lines(markdown_lines)
        if vim.tbl_isempty(markdown_lines) then return end

        local bufnr,contents_winid,_,border_winid = window.fancy_floating_markdown(markdown_lines, {
          max_hover_width = config.max_hover_width,
          border_style = config.border_style,
        })

        lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, contents_winid)
        lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, border_winid)
        return bufnr,contents_winid
    end)
end

function hover.render_hover_doc()
  local params = util.make_position_params()
  vim.lsp.buf_request(0,'textDocument/hover', params,call_back)
end

function hover.has_saga_hover()
  local has_hover_win,_ = pcall(api.nvim_win_get_var,0,'lspsaga_hoverwin_data')
  if has_hover_win then return true end
end

-- 1 mean down -1 mean up
function hover.scroll_in_hover(direction)
  local has_hover_win,hover_data = pcall(api.nvim_win_get_var,0,'lspsaga_hoverwin_data')
  if not has_hover_win then return end
  local hover_win,height,current_win_lnum,last_lnum = hover_data[1],hover_data[2],hover_data[3],hover_data[4]
  if direction == 1 then
    current_win_lnum = current_win_lnum + height
    if current_win_lnum >= last_lnum then
      current_win_lnum = last_lnum
    end
  elseif direction == -1 then
    if current_win_lnum <= last_lnum and current_win_lnum > 0 then
      current_win_lnum = current_win_lnum - height
    end
    if current_win_lnum < 0 then
      current_win_lnum = 1
    end
  end
  api.nvim_win_set_cursor(hover_win,{current_win_lnum,0})
  api.nvim_win_set_var(0,'lspsaga_hoverwin_data',{hover_win,height,current_win_lnum,last_lnum})
end

return hover
