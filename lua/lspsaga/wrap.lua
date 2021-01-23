local wrap = {}

-- If the content too long.
-- auto wrap according width
-- fill the space with wrap text
function wrap.wrap_text(text,width,fill)
  local ret = {}
  -- if text width < width just return it
  if #text < width then
    table.insert(ret,text)
    return ret
  end

  local stra = text:sub(1,width)
  local strb = text:sub(width+1,#text)

  table.insert(ret,stra)
  if fill then
    table.insert(ret,' '..strb)
  else
    table.insert(ret,strb)
  end

  return ret
end

function wrap.wrap_contents(contents,width)
  if type(contents) ~= "table" then
    error("Wrong params type of function wrap_contents")
    return
  end

  for idx, text in ipairs(contents) do
    if #text > width then
      local tmp = wrap.wrap_text(text,width,true)
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

