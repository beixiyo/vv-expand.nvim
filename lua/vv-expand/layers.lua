-- vv-expand.layers: 四层扩张策略
-- 每层签名: (cur, config) -> range | nil
-- 返回 range 的合法性（是否严格包含 cur）由调用方校验

local R = require('vv-expand.range')

local M = {}

-- ========== Layer 0: word (iw → 逐段 subword | iW) ==========

function M.word(cur, cfg)
  if cur[1] ~= cur[3] then return nil end
  local lnum = cur[1]
  local line = R.line_text(lnum)
  if line == '' then return nil end

  local cur_s, cur_e = cur[2], cur[4]
  local delims = cfg.subword_delimiters

  -- iw: [%w_]+ 连续字母数字下划线
  local s, e = cur_s, cur_e
  while s > 1 and line:sub(s - 1, s - 1):match('[%w_]') do s = s - 1 end
  while e < #line and line:sub(e + 1, e + 1):match('[%w_]') do e = e + 1 end
  local iw = { lnum, s, lnum, e }
  if R.contains_strict(iw, cur) then return iw end

  if delims then
    -- 逐段扩张：遇到分隔符停下，走完后交给 pair 层
    local best, best_size = nil, math.huge
    local function try(r)
      if R.contains_strict(r, cur) then
        local sz = R.size(r)
        if sz < best_size then best, best_size = r, sz end
      end
    end

    if cur_s > 1 then
      local ch = line:sub(cur_s - 1, cur_s - 1)
      if delims:find(ch, 1, true) then
        local ls = cur_s - 1
        while ls > 1 and line:sub(ls - 1, ls - 1):match('[%w_]') do ls = ls - 1 end
        if ls < cur_s - 1 then try({ lnum, ls, lnum, cur_e }) end
      end
    end

    if cur_e < #line then
      local ch = line:sub(cur_e + 1, cur_e + 1)
      if delims:find(ch, 1, true) then
        local re = cur_e + 1
        while re < #line and line:sub(re + 1, re + 1):match('[%w_]') do re = re + 1 end
        if re > cur_e + 1 then try({ lnum, cur_s, lnum, re }) end
      end
    end

    return best
  end

  -- iW: [^%s]+ 连续非空白（仅 subword_delimiters 未配置时）
  s, e = cur_s, cur_e
  while s > 1 and not line:sub(s - 1, s - 1):match('%s') do s = s - 1 end
  while e < #line and not line:sub(e + 1, e + 1):match('%s') do e = e + 1 end
  local iW = { lnum, s, lnum, e }
  if R.contains_strict(iW, cur) then return iW end

  return nil
end

-- ========== Layer 1: pair (本行成对字符) ==========

-- word-boundary 规则：分隔字符（run）两侧同时是 ASCII 字母数字时视为词内（snake_case 的 _、
-- a*b 的 *、kebab 的 -），不参与配对；其余（标点、空白、行首行尾、CJK）都是合法分隔位

-- 找出 ch 在本行的所有成对位置（含 markdown 风格的连续 run 多层嵌套）。
-- run = 连续相同字符（如 ** / __）视作一个分隔 token；run 按出现顺序 parity 配对
-- （run#1 开 ↔ run#2 闭、run#3 ↔ run#4 ...），run 内字符由内向外逐层嵌套，
-- 使 **x** 能逐层扩张 x → *x* → **x**；单字符 run 退化为普通成对（不影响 'a'、'a' 'b' 等）。
-- 返回 { {s,e}, ... }，调用方对每个 try_pair 生成内/外候选，再由 try 的 contains_strict 选最内层。
local function find_same_char_pairs(line, ch)
  local n = #line
  local runs = {}
  local i = 1
  while i <= n do
    if line:sub(i, i) == ch then
      local j = i
      while j < n and line:sub(j + 1, j + 1) == ch do j = j + 1 end
      -- run [i,j] 的词内判断：左邻与右邻同为 ASCII 字母数字才算词内（如 a*b 的 *、foo_bar 的 _）
      local before = i > 1 and line:sub(i - 1, i - 1) or ''
      local after = j < n and line:sub(j + 1, j + 1) or ''
      if not (before:match('[%w]') and after:match('[%w]')) then
        runs[#runs + 1] = { i, j }
      end
      i = j + 1
    else
      i = i + 1
    end
  end

  local out = {}
  for k = 1, #runs - 1, 2 do
    local a, b = runs[k], runs[k + 1] -- a=开 run，b=闭 run
    local levels = math.min(a[2] - a[1] + 1, b[2] - b[1] + 1)
    for t = 1, levels do
      -- 第 t 层（由内向外）：开 run 右数第 t 个 ↔ 闭 run 左数第 t 个
      out[#out + 1] = { a[2] - (t - 1), b[1] + (t - 1) }
    end
  end
  return out
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
    for _, p in ipairs(find_same_char_pairs(line, ch)) do
      try_pair(p[1], p[2])
    end
  end
  for _, pair in ipairs(cfg.pairs.nested) do
    local p = find_nested_pair(line, pair[1], pair[2], cur[2], cur[4])
    if p then try_pair(p[1], p[2]) end
  end
  return best
end

-- ========== Layer 2: LSP textDocument/selectionRange ==========

-- 0-based byte 列 → LSP position encoding 的 code unit（utf-8 为恒等）
local function byte_to_lsp_char(line, byte0, enc)
  if enc == 'utf-8' or byte0 <= 0 then return math.max(0, byte0) end
  local ok, idx = pcall(vim.str_utfindex, line, enc, byte0, false)
  return ok and idx or byte0
end

-- LSP code unit → 0-based byte 偏移（utf-8 为恒等）
local function lsp_char_to_byte(line, char, enc)
  if enc == 'utf-8' or char <= 0 then return math.max(0, char) end
  local ok, idx = pcall(vim.str_byteindex, line, enc, char, false)
  return ok and idx or char
end

function M.lsp(cur, cfg)
  local clients = vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/selectionRange' })
  if #clients == 0 then return nil end
  local buf = vim.api.nvim_get_current_buf()
  local client = clients[1]
  local enc = client.offset_encoding or 'utf-16'

  -- cur[2] 是 1-based byte col；LSP position 的 character 是 position encoding（默认 utf-16）
  -- 的 code unit，含多字节字符的行上二者不等，必须按行文本换算
  local cur_line = R.line_text(cur[1])
  local req_char = byte_to_lsp_char(cur_line, cur[2] - 1, enc)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    positions = { { line = cur[1] - 1, character = req_char } },
  }
  local ok, resp = pcall(function()
    return client:request_sync('textDocument/selectionRange', params, cfg.lsp_timeout, buf)
  end)
  if not ok or not resp or not resp.result or not resp.result[1] then return nil end

  local sel = resp.result[1]
  while sel do
    local r = sel.range
    local s_lnum = r.start.line + 1
    local e_lnum = r['end'].line + 1
    -- 返回的 character 是 code unit，按各自行文本转回字节列
    local s_col = lsp_char_to_byte(R.line_text(s_lnum), r.start.character, enc) + 1
    -- end.character 是 0-based exclusive；转出的 0-based exclusive 字节偏移直接当 1-based
    -- inclusive 字节列用（exclusive→inclusive 的 -1 与 0→1based 的 +1 抵消，与 treesitter 层一致）
    local e_col = lsp_char_to_byte(R.line_text(e_lnum), r['end'].character, enc)
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
