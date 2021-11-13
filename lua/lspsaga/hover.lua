local api, lsp, util = vim.api, vim.lsp, vim.lsp.util
local window = require "lspsaga.window"
local action = require "lspsaga.action"
local npcall = vim.F.npcall
local hover = {}

local function focusable_float(unique_name, fn)
  if npcall(api.nvim_win_get_var, 0, unique_name) then
    return api.nvim_command "wincmd p"
  end
  local bufnr = api.nvim_get_current_buf()
  local pbufnr, pwinnr = fn()
  if pbufnr then
    api.nvim_win_set_var(pwinnr, unique_name, bufnr)
    return pbufnr, pwinnr
  end
end

hover.handler = function(_, result, ctx, _)
  focusable_float(ctx.method, function()
    if not (result and result.contents) then
      return
    end
    local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)
    markdown_lines = lsp.util.trim_empty_lines(markdown_lines)
    if vim.tbl_isempty(markdown_lines) then
      return
    end
    window.nvim_win_try_close()
    local bufnr, winid = window.fancy_floating_markdown(markdown_lines)

    lsp.util.close_preview_autocmd({
      "CursorMoved",
      "BufHidden",
      "BufLeave",
      "InsertCharPre",
    }, winid)
    return bufnr, winid
  end)
end

function hover.render_hover_doc()
  --if has diagnostic window close
  window.nvim_win_try_close()
  local params = util.make_position_params()
  vim.lsp.buf_request(0, "textDocument/hover", params, hover.handler)
end

function hover.has_saga_hover()
  local has_hover_win, datas = pcall(api.nvim_win_get_var, 0, "lspsaga_hoverwin_data")
  if not has_hover_win then
    return false
  end
  if api.nvim_win_is_valid(datas[1]) then
    return true
  end
  return false
end

function hover.close_hover_window()
  if hover.has_saga_hover() then
    local data = npcall(api.nvim_win_get_var, 0, "lspsaga_hoverwin_data")
    api.nvim_win_close(data[1], true)
  end
end

-- 1 mean down -1 mean up
function hover.scroll_in_hover(direction)
  local has_hover_win, hover_data = pcall(api.nvim_win_get_var, 0, "lspsaga_hoverwin_data")
  if not has_hover_win then
    return
  end
  local hover_win, height, current_win_lnum, last_lnum = hover_data[1], hover_data[2], hover_data[3], hover_data[4]
  if not api.nvim_win_is_valid(hover_win) then
    return
  end
  current_win_lnum = action.scroll_in_win(hover_win, direction, current_win_lnum, last_lnum, height)
  api.nvim_win_set_var(0, "lspsaga_hoverwin_data", { hover_win, height, current_win_lnum, last_lnum })
end

return hover
