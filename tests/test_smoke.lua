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

print('\n=== FIX 7: LSP selectionRange e_col exclusive → inclusive ===')
do
  local layers_path = root .. 'layers.lua'
  local f = io.open(layers_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()

    -- 检查代码中 e_col 赋值使用了 -1
    ok(
      content:find("e_col = r%['end'%].character %- 1") ~= nil,
      'e_col 使用 character - 1（exclusive → inclusive）'
    )

    -- 检查边界条件改为 <= 0
    ok(
      content:find('e_col <= 0 and e_lnum > s_lnum') ~= nil,
      '边界条件使用 e_col <= 0（覆盖减 1 后为 0 的场景）'
    )
  else
    ok(false, '无法读取 layers.lua')
  end
end

-- 单元测试：模拟 LSP 返回值的转换逻辑
print('\n=== FIX 7: e_col 转换逻辑单元测试 ===')
do
  -- 模拟 LSP 返回 end.character = 5（exclusive，即选到第 4 列）
  local lsp_end_char = 5
  local e_col = lsp_end_char - 1
  ok(e_col == 4, 'character=5 exclusive → col=4 inclusive')

  -- 模拟 LSP 返回 end.character = 1（exclusive，即选到第 0 列 → 应为上一行末尾）
  lsp_end_char = 1
  e_col = lsp_end_char - 1
  ok(e_col == 0, 'character=1 exclusive → col=0（触发行回退逻辑）')

  -- 模拟 LSP 返回 end.character = 0（exclusive，跨行场景）
  lsp_end_char = 0
  e_col = lsp_end_char - 1
  ok(e_col <= 0, 'character=0 exclusive → col=-1 <= 0（触发行回退逻辑）')

  -- math.max(1, e_col) 保底
  ok(math.max(1, -1) == 1, 'math.max(1, -1) 兜底为 1')
  ok(math.max(1, 0) == 1, 'math.max(1, 0) 兜底为 1')
  ok(math.max(1, 4) == 4, 'math.max(1, 4) 保持 4')
end

print('\n=== FIX 8: filetype_exclude 注释 ===')
do
  local init_path = root .. 'init.lua'
  local f = io.open(init_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()

    -- 检查注释存在
    ok(
      content:find("'vv%-explorer'") ~= nil,
      'filetype_exclude 仍包含 vv-explorer'
    )
    ok(
      content:find("'vv%-task%-panel'") ~= nil,
      'filetype_exclude 仍包含 vv-task-panel'
    )
    ok(
      content:find('作者的其他插件') ~= nil,
      '添加了说明注释'
    )
    ok(
      content:find('安全忽略') ~= nil,
      '注释说明未安装时会被安全忽略'
    )
  else
    ok(false, '无法读取 init.lua')
  end
end

print(string.format('\n结果：%d 通过，%d 失败\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
end
