-- vv-expand.range: 选区数据结构 + UTF-8 字符边界 + visual 读写
-- range = { s_lnum, s_col, e_lnum, e_col }  1-indexed，inclusive，byte col

local M = {}

function M.eq(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

function M.contains_strict(outer, inner)
  local start_le = outer[1] < inner[1] or (outer[1] == inner[1] and outer[2] <= inner[2])
  local end_ge = outer[3] > inner[3] or (outer[3] == inner[3] and outer[4] >= inner[4])
  return start_le and end_ge and not M.eq(outer, inner)
end

-- 同层内比较 range 大小（用于 pair 层挑最内层）
function M.size(r)
  return (r[3] - r[1]) * 1e6 + (r[4] - r[2])
end

function M.line_text(lnum)
  return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ''
end

function M.last_col(lnum)
  return math.max(1, #M.line_text(lnum))
end

function M.clamp_col(lnum, col)
  local len = #M.line_text(lnum)
  if len == 0 then return 1 end
  if col < 1 then return 1 end
  if col > len then return len end
  return col
end

-- nvim_win_set_cursor 落在 multi-byte char 内部会被回退到字符首字节，
-- 导致 set_visual 的 end 位置和 getpos("'>") 读回的 col 错位 → 扩张后视觉上无变化
function M.to_char_start(lnum, col)
  local line = M.line_text(lnum)
  if #line == 0 or col < 1 then return 1 end
  if col > #line then return #line end
  local b = line:byte(col)
  while b and b >= 0x80 and b < 0xC0 and col > 1 do
    col = col - 1
    b = line:byte(col)
  end
  return col
end

function M.to_char_end(lnum, col)
  local line = M.line_text(lnum)
  if #line == 0 or col < 1 then return 1 end
  if col > #line then return #line end
  col = M.to_char_start(lnum, col)
  local b = line:byte(col)
  local len = 1
  if b and b >= 0xF0 then len = 4
  elseif b and b >= 0xE0 then len = 3
  elseif b and b >= 0xC0 then len = 2
  end
  return math.min(#line, col + len - 1)
end

-- 读取当前选区（visual）或光标位置（normal），已做 UTF-8 边界规整
function M.get_cur()
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local a = vim.fn.getpos('v')
    local b = vim.fn.getpos('.')
    local sr, sc, er, ec = a[2], a[3], b[2], b[3]
    if sr > er or (sr == er and sc > ec) then
      sr, sc, er, ec = er, ec, sr, sc
    end
    if mode == 'V' then
      sc = 1
      ec = M.last_col(er)
    end
    -- 光标在 multi-byte char 首字节时，getpos 返回首字节 col；visual 视觉上包了整字，
    -- 把 ec 规整到该字符末字节，和 set_visual 压栈的 range 才能对上
    ec = M.to_char_end(er, ec)
    return { sr, sc, er, ec }
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  return { pos[1], pos[2] + 1, pos[1], pos[2] + 1 }
end

-- 把 visual 选区设到 r；会先退出已有 visual，再重新进入
function M.set_visual(r)
  if vim.fn.mode():match('[vV\22]') then
    vim.cmd('normal! \27')
  end
  -- 光标必须落在字符首字节（0-idx），否则 nvim 会回退到字符首字节导致选区错位
  local s_col = M.to_char_start(r[1], M.clamp_col(r[1], r[2]))
  local e_col = M.to_char_start(r[3], M.clamp_col(r[3], r[4]))
  vim.api.nvim_win_set_cursor(0, { r[1], s_col - 1 })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { r[3], e_col - 1 })
end

return M
