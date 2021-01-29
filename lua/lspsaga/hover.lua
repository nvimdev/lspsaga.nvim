local lsp,util = vim.lsp,vim.lsp.util
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

return hover
