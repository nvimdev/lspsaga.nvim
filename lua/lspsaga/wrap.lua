local wrap = {}

-- If the content too long.
-- auto wrap according width
-- fill the space with wrap text
function wrap.wrap_text(text,width,opts)
  opts = opts or {}
  local ret = {}
  local space = ' '
  -- if text width < width just return it
  if #text <= width then
    table.insert(ret,text)
    return ret
  end

  local _truncate = function (t,w)
    local tmp = t
    local tbl = {}
    while true do
      if #tmp > w then
        table.insert(tbl,tmp:sub(1,w))
        tmp = tmp:sub(w+1)
      else
        table.insert(tbl,tmp)
        break
      end
    end
    return tbl
  end
  ret = _truncate(text,width)

  if opts.fill then
    for i=2,#ret,1 do
      ret[i] = space .. ret[i]
    end
  end

  return ret
end

function wrap.wrap_contents(contents,width,opts)
  opts = opts or {}
  if type(contents) ~= "table" then
    error("Wrong params type of function wrap_contents")
    return
  end

  for idx, text in ipairs(contents) do
    if #text > width then
      local tmp = wrap.wrap_text(text,width,opts)
      for i,j in ipairs(tmp) do
        table.insert(contents,idx+i-1,j)
      end
      table.remove(contents,idx+#tmp)
    end
  end

  return contents
end

function wrap.add_truncate_line(contents)
  local line_widths = {}
  local width = 0
  local truncate_line = '─'

  for i,line in ipairs(contents) do
    line_widths[i] = vim.fn.strdisplaywidth(line)
    width = math.max(line_widths[i], width)
  end

  for _=1,width,1 do
    truncate_line = truncate_line .. '─'
  end

  return truncate_line
end

return wrap
