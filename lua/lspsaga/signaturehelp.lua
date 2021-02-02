local util,api = vim.lsp.util,vim.api
local npcall = vim.F.npcall
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local wrap = require('lspsaga.wrap')

local function find_window_by_var(name, value)
  for _, win in ipairs(api.nvim_list_wins()) do
    if npcall(api.nvim_win_get_var, win, name) == value then
      return win
    end
  end
end

local function focusable_float(unique_name, fn)
  -- Go back to previous window if we are in a focusable one
  if npcall(api.nvim_win_get_var, 0, unique_name) then
    return api.nvim_command("wincmd p")
  end
  local bufnr = api.nvim_get_current_buf()
  do
    local win = find_window_by_var(unique_name, bufnr)
    if win and api.nvim_win_is_valid(win) and not vim.fn.pumvisible() then
      api.nvim_set_current_win(win)
      api.nvim_command("stopinsert")
      return
    end
  end
  local pbufnr, pwinnr,_,_= fn()
  if pbufnr then
    api.nvim_win_set_var(pwinnr, unique_name, bufnr)
    return pbufnr, pwinnr
  end
end

local function focusable_preview(unique_name, fn)
  return focusable_float(unique_name, function()
    local contents,_ = fn()
    -- TODO: not sure this is better
    local filetype = api.nvim_buf_get_option(0,'filetype')
    vim.validate {
      contents = { contents, 't' };
      filetype = { filetype, 's', true };
    }
    local opts = {}
    -- Clean up input: trim empty lines from the end, pad
    contents = util._trim_and_pad(contents, opts)
    -- Compute size of float needed to show (wrapped) lines
    opts.wrap_at = opts.wrap_at or (vim.wo["wrap"] and api.nvim_win_get_width(0))
    local width, _ = util._make_floating_popup_size(contents, opts)
    if width > #contents[1] then
      width = #contents[1]
    end

    local WIN_WIDTH = vim.fn.winwidth(0)
    local max_width = WIN_WIDTH * 0.7
    if width > max_width then
      width = max_width
    end

    contents = wrap.wrap_contents(contents,width)

    if #contents ~= 1 then
      local truncate_line = wrap.add_truncate_line(contents)
      table.insert(contents,2,truncate_line)
    end
    local border_opts = {
      border = config.border_style,
      highlight = 'LspSagaSignatureHelpBorder'
    }

    local content_opts = {
      contents = contents,
      filetype = filetype,
    }

    local cb,cw,_,bw = window.create_float_window(content_opts,border_opts)
    util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"}, cw)
    util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"}, bw)
    return cb,cw
  end)
end

local call_back = function(_, method, result)
  if not (result and result.signatures and result.signatures[1]) then
    print('No signature help available')
    return
  end
  local lines = util.convert_signature_help_to_markdown_lines(result)
  lines = util.trim_empty_lines(lines)
  if vim.tbl_isempty(lines) then
    print('No signature help available')
    return
  end
  focusable_preview(method, function()
    return lines, util.try_trim_markdown_code_blocks(lines)
  end)
end

local signature_help = function()
  local params = util.make_position_params()
  vim.lsp.buf_request(0,'textDocument/signatureHelp', params,call_back)
end

return {
  signature_help = signature_help
}
