-- vv-expand.layers: 四层扩张策略
-- 每层签名: (cur, config) -> range | nil
-- 返回 range 的合法性（是否严格包含 cur）由调用方校验

local R = require('vv-expand.range')

local M = {}

-- ========== Layer 0: word (先 iw 再 iW) ==========

function M.word(cur, _cfg)
  if cur[1] ~= cur[3] then return nil end
  local lnum = cur[1]
  local line = R.line_text(lnum)
  if line == '' then return nil end

  local cur_s, cur_e = cur[2], cur[4]

  -- iw: [%w_]+ 连续字母数字下划线
  local s, e = cur_s, cur_e
  while s > 1 and line:sub(s - 1, s - 1):match('[%w_]') do s = s - 1 end
  while e < #line and line:sub(e + 1, e + 1):match('[%w_]') do e = e + 1 end
  local iw = { lnum, s, lnum, e }
  if R.contains_strict(iw, cur) then return iw end

  -- iW: [^%s]+ 连续非空白
  s, e = cur_s, cur_e
  while s > 1 and not line:sub(s - 1, s - 1):match('%s') do s = s - 1 end
  while e < #line and not line:sub(e + 1, e + 1):match('%s') do e = e + 1 end
  local iW = { lnum, s, lnum, e }
  if R.contains_strict(iW, cur) then return iW end

  return nil
end

-- ========== Layer 1: pair (本行成对字符) ==========

-- word-boundary 规则：char 两侧同时是 ASCII 字母数字时视为词内字符（snake_case 的 _、
-- kebab-case 的 -），不参与配对；其余（标点、空白、行首行尾、CJK）都是合法分隔符位
local function is_delim_pos(line, col)
  local before = col > 1 and line:sub(col - 1, col - 1) or ''
  local after = col < #line and line:sub(col + 1, col + 1) or ''
  return not (before:match('[%w]') and after:match('[%w]'))
end

local function find_same_char_pair(line, ch, cur_s, cur_e)
  local pos = {}
  local i = 1
  while true do
    local p = line:find(ch, i, true)
    if not p then break end
    if is_delim_pos(line, p) then
      pos[#pos + 1] = p
    end
    i = p + 1
  end
  -- 从左到右两两成对 (1,2) (3,4) ...，取最内层严格包含 cur 的那对
  for k = 1, #pos - 1, 2 do
    local s, e = pos[k], pos[k + 1]
    if s < cur_s and e >= cur_e then return { s, e } end
  end
  return nil
end

local function find_nested_pair(line, open_ch, close_ch, cur_s, cur_e)
  local stack, best = {}, nil
  for col = 1, #line do
    local c = line:sub(col, col)
    if c == open_ch then
      stack[#stack + 1] = col
    elseif c == close_ch then
      local s = table.remove(stack)
      if s and s < cur_s and col >= cur_e then
        if not best or (col - s) < (best[2] - best[1]) then
          best = { s, col }
        end
      end
    end
  end
  return best
end

function M.pair(cur, cfg)
  if cur[1] ~= cur[3] then return nil end
  local lnum = cur[1]
  local line = R.line_text(lnum)
  if line == '' then return nil end

  local best, best_size = nil, math.huge
  local function try(r)
    if R.contains_strict(r, cur) then
      local sz = R.size(r)
      if sz < best_size then
        best, best_size = r, sz
      end
    end
  end

  -- 每对字符产生两个候选：内部（不含首尾分隔符）与外部（含首尾），由 try 过滤掉非严格包含的
  local function try_pair(s, e)
    if e > s + 1 then try({ lnum, s + 1, lnum, e - 1 }) end
    try({ lnum, s, lnum, e })
  end

  for _, ch in ipairs(cfg.pairs.same) do
    local p = find_same_char_pair(line, ch, cur[2], cur[4])
    if p then try_pair(p[1], p[2]) end
  end
  for _, pair in ipairs(cfg.pairs.nested) do
    local p = find_nested_pair(line, pair[1], pair[2], cur[2], cur[4])
    if p then try_pair(p[1], p[2]) end
  end
  return best
end

-- ========== Layer 2: LSP textDocument/selectionRange ==========

function M.lsp(cur, cfg)
  local clients = vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/selectionRange' })
  if #clients == 0 then return nil end
  local buf = vim.api.nvim_get_current_buf()
  local client = clients[1]
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    positions = { { line = cur[1] - 1, character = cur[2] - 1 } },
  }
  local ok, resp = pcall(function()
    return client:request_sync('textDocument/selectionRange', params, cfg.lsp_timeout, buf)
  end)
  if not ok or not resp or not resp.result or not resp.result[1] then return nil end

  local sel = resp.result[1]
  while sel do
    local r = sel.range
    local s_lnum = r.start.line + 1
    local s_col = r.start.character + 1
    local e_lnum = r['end'].line + 1
    -- LSP end.character 是 exclusive 的，转为 inclusive 需 -1
    local e_col = r['end'].character - 1
    if e_col <= 0 and e_lnum > s_lnum then
      e_lnum = e_lnum - 1
      e_col = R.last_col(e_lnum)
    end
    local rng = { s_lnum, s_col, e_lnum, math.max(1, e_col) }
    if R.contains_strict(rng, cur) then return rng end
    sel = sel.parent
  end
  return nil
end

-- ========== Layer 3: Treesitter 父节点 ==========

function M.treesitter(cur, _cfg)
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then return nil end
  local node = vim.treesitter.get_node({
    bufnr = 0,
    pos = { cur[1] - 1, math.max(0, cur[2] - 1) },
  })
  if not node then return nil end
  while node do
    local sr, sc, er, ec = node:range()
    local e_lnum = er + 1
    local e_col = ec
    if ec == 0 and er > sr then
      e_lnum = er
      e_col = R.last_col(e_lnum)
    end
    local rng = { sr + 1, sc + 1, e_lnum, math.max(1, e_col) }
    if R.contains_strict(rng, cur) then return rng end
    node = node:parent()
  end
  return nil
end

-- ========== Layer 4: 行扩张兜底 ==========

function M.line(cur, _cfg)
  local total = vim.api.nvim_buf_line_count(0)
  local is_full = cur[2] == 1 and cur[4] >= R.last_col(cur[3])
  if not is_full then
    return { cur[1], 1, cur[3], R.last_col(cur[3]) }
  end
  local new_s = math.max(1, cur[1] - 1)
  local new_e = math.min(total, cur[3] + 1)
  if new_s == cur[1] and new_e == cur[3] then return nil end
  return { new_s, 1, new_e, R.last_col(new_e) }
end

return M
