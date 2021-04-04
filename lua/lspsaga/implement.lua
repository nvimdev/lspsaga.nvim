local lsp,api = vim.lsp,vim.api
local config = require('lspsaga').config_values
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local implement = {}

function implement.lspsaga_implementation(timeout_ms)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  local method = "textDocument/implementation"
  local params = lsp.util.make_position_params()
  local result = vim.lsp.buf_request_sync(0,method,params,timeout_ms or 1000)
  if result == nil or vim.tbl_isempty(result) then
    print("No location found: " .. method)
    return nil
  end
  result = {vim.tbl_deep_extend("force", {}, unpack(result))}

  if vim.tbl_islist(result) and not vim.tbl_isempty(result[1]) then
    local uri = result[1].result[1].uri or result[1].result[1].targetUri
    if #uri == 0 then return end
    local bufnr = vim.uri_to_bufnr(uri)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
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
    content = vim.list_extend({config.definition_preview_icon.."Definition Preview",""},content)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    local opts = {
      relative = "cursor",
      style = "minimal",
    }
    local WIN_WIDTH = vim.fn.winwidth(0)
    local max_width = math.floor(WIN_WIDTH * 0.5)
    local width, _ = vim.lsp.util._make_floating_popup_size(content, opts)

    if width > max_width then
      opts.width = max_width
    end

    local content_opts = {
      contents = content,
      filetype = filetype,
    }

    local bf,wi = window.create_win_with_border(content_opts,opts)
    vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"},
                                        wi)
    vim.api.nvim_buf_add_highlight(bf,-1,"DefinitionPreviewTitle",0,0,-1)

    api.nvim_buf_set_var(0,'lspsaga_def_preview',{wi,1,config.max_preview_lines,10})
  end
end

return implement
