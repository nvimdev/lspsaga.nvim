local api = vim.api
local ns = vim.api.nvim_create_namespace('DiagnosticCurLine')

---render diagnostic virtual text only on current line
---make sure disable neovim builtin diagnostic virtual
---text by using `vim.diagnsotic.config`
---```lua
---vim.diagnostic.config({
---   virtual_text = false
---})
---```
local function diag_on_current()
  api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
      local group_name = 'DiagnosticVirtOn' .. args.buf
      local group = api.nvim_get_autocmds({ group = group_name })
      if not group then
        api.nvim_create_autocmd('CursorHold', {
          group = api.nvim_create_augroup(group_name, { clear = false }),
          buffer = args.buf,
          callback = function()
            if vim.opt.time <= 100 then
              vim.notify(
                '[Lspsaga] for better experience on diagnostic on current line please set vim.opt.updatime to 100',
                vim.log.levels.WARN
              )
            end
            pcall(vim.api.nvim_buf_clear_namespace, args.buf, ns, -1, -1)
            local curline = vim.api.nvim_win_get_cursor(0)[1]
            local diagnostics = vim.diagnostic.get(args.buf, { lnum = curline - 1 })
            local virt_texts = { { (' '):rep(4) } }
            for _, diag in ipairs(diagnostics) do
              virt_texts[#virt_texts + 1] =
                { diag.message, 'Diagnostic' .. vim.diagnostic.severity[diag.severity] }
            end
            api.nvim_buf_set_extmark(args.buf, ns, curline - 1, 0, {

              virt_text = virt_texts,
              hl_mode = 'combine',
            })
          end,
        })
      end
    end,
  })
end

return {
  diag_on_current = diag_on_current,
}
