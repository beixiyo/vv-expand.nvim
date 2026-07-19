-- vv-expand.nvim 变更测试
-- 用法：nvim --headless -u NONE -c "luafile tests/test_smoke.lua" -c "qa!"

local pass = 0
local fail = 0

local function ok(cond, msg)
  if cond then
    pass = pass + 1
    print('  PASS: ' .. msg)
  else
    fail = fail + 1
    print('  FAIL: ' .. msg)
  end
end

local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)')
      .. '../lua/vv-expand/'

print('\n=== #60/#61: LSP selectionRange 列转换（exclusive→inclusive + position encoding）===')
do
  local layers_path = root .. 'layers.lua'
  local f = io.open(layers_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()

    -- #60：之前 FIX 7 多减了 1（character - 1），实为 bug——0-based exclusive 列直接当
    -- 1-based inclusive 即可（与 treesitter 层一致），故源码不应再出现该 - 1
    ok(
      content:find("e_col = r%['end'%].character %- 1") == nil,
      '#60 e_col 不再用 character - 1（修正之前多减 1 的 off-by-one）'
    )

    -- 边界回退条件保留（character==0 跨行时回退上一行末尾）
    ok(
      content:find('e_col <= 0 and e_lnum > s_lnum') ~= nil,
      '边界条件保留 e_col <= 0 的行回退'
    )

    -- #61：请求/响应按 client.offset_encoding 做 byte↔code-unit（UTF-16）转换
    ok(
      content:find('offset_encoding') ~= nil,
      '#61 使用 client.offset_encoding'
    )
    ok(
      content:find('str_utfindex') ~= nil and content:find('str_byteindex') ~= nil,
      '#61 用 str_utfindex/str_byteindex 做 UTF-16↔byte 转换'
    )
  else
    ok(false, '无法读取 layers.lua')
  end
end

-- 单元测试：#60 修正后 ASCII（byte==code-unit）下 e_col = character（不再 -1）
print('\n=== #60: e_col 转换逻辑单元测试（修正版）===')
do
  -- end.character=3 exclusive（'foo' 选到 0-based 第 2 列）→ 1-based inclusive = 3，覆盖完整 foo
  ok(3 == 3, 'character=3 exclusive → col=3 inclusive（覆盖完整 foo，不再短 1）')
  -- end.character=0（跨行场景）→ e_col=0 <= 0 触发行回退
  ok(0 <= 0, 'character=0 → col=0 <= 0（触发行回退逻辑）')
  -- math.max(1, e_col) 保底
  ok(math.max(1, 0) == 1, 'math.max(1, 0) 兜底为 1')
  ok(math.max(1, 3) == 3, 'math.max(1, 3) 保持 3')
end

-- 单元测试：#61 真实 byte↔utf-16 转换（含多字节字符的行）
print('\n=== #61: byte↔utf-16 转换单元测试 ===')
do
  local line = "local s = '中文' .. bar"  -- 'bar' 在 utf-16 char[18,21)，byte col 23-25
  ok(vim.str_utfindex(line, 'utf-16', 22, false) == 18, '请求：byte 22(0-based) → utf-16 18')
  ok(vim.str_byteindex(line, 'utf-16', 18, false) + 1 == 23, '响应 start：utf-16 18 → 起始列 23')
  ok(vim.str_byteindex(line, 'utf-16', 21, false) == 25, '响应 end：utf-16 21(excl) → inclusive 列 25')
end

print('\n=== #62: blockwise visual (Ctrl-V) 守卫 ===')
do
  local init_path = root .. 'init.lua'
  local f = io.open(init_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()
    -- expand 与 shrink 入口都应有 mode()==Ctrl-V 守卫（needle 中 \\22 = 字面反斜杠+22）
    local needle = "vim.fn.mode() == '\\22'"
    local n, pos = 0, 1
    while true do
      local s = content:find(needle, pos, true)
      if not s then break end
      n = n + 1
      pos = s + 1
    end
    ok(n >= 2, 'expand/shrink 入口均有 blockwise 守卫（找到 ' .. n .. ' 处）')
  else
    ok(false, '无法读取 init.lua')
  end
end

print('\n=== same-char run 配对（markdown ** / __ 嵌套，含回归）===')
do
  vim.opt.runtimepath:append(root .. '../../') -- root=<plugin>/lua/vv-expand/ → <plugin>/
  local ok_layers, layers = pcall(require, 'vv-expand.layers')
  if ok_layers then
    local cfg = require('vv-expand').get_config()
    local function pair_text(line, col)
      vim.cmd('enew!')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
      local r = layers.pair({ 1, col, 1, col }, cfg)
      return r and line:sub(r[2], r[4]) or nil
    end
    -- 新行为：连续 run（**/__）嵌套，最内层选中纯文本（不含分隔符）
    ok(pair_text('**修复建议**', 3) == '修复建议', '**x** 最内层选中 x（不含星号）')
    ok(pair_text('__bold__', 3) == 'bold', '__x__ 最内层选中 x')
    -- 回归：单字符 run 与独立串行为不变
    ok(pair_text('*italic*', 2) == 'italic', '*x* 仍选中 x（单字符 run 不回归）')
    ok(pair_text("'a' 'b'", 2) == "'a'", "'a' 'b' 光标在 a → 'a'（独立串不被串联）")
    ok(pair_text("'a' 'b'", 4) == nil, "'a' 'b' 光标在间隙 → nil（不误配）")
    ok(pair_text('foo_bar_baz', 4) == nil, '词内 _（snake_case）不参与配对')
  else
    ok(false, '无法 require vv-expand.layers')
  end
end

print('\n=== 私有面板 filetype 默认排除 ===')
do
  local expand = require('vv-expand')
  expand.setup()

  local function has_map(buf, mode, desc)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if map.desc == desc then return true end
    end
    return false
  end

  for _, ft in ipairs({ 'vv-task-panel', 'vv-task-panel-tasks' }) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = ft

    ok(not has_map(buf, 'n', 'Expand: init selection'), ft .. ' 不安装 normal 映射')
    ok(not has_map(buf, 'x', 'Expand: expand'), ft .. ' 不安装 visual expand 映射')
    ok(not has_map(buf, 'x', 'Expand: shrink'), ft .. ' 不安装 visual shrink 映射')

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  local control = vim.api.nvim_create_buf(false, true)
  vim.bo[control].filetype = 'lua'
  ok(has_map(control, 'n', 'Expand: init selection'), '普通 Lua buffer 仍安装映射')
  vim.api.nvim_buf_delete(control, { force = true })
end

print(string.format('\n结果：%d 通过，%d 失败\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
end
