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

local this = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local plugin_root = vim.fn.fnamemodify(this, ':h:h')
vim.opt.runtimepath:append(plugin_root)

print('\n=== LSP selectionRange: UTF-16 请求与 exclusive 响应范围 ===')
do
  local layers = require('vv-expand.layers')
  local old_get_clients = vim.lsp.get_clients
  local request_character
  local client = {
    offset_encoding = 'utf-16',
    request_sync = function(_, _, params)
      request_character = params.positions[1].character
      return {
        result = {
          {
            range = {
              start = { line = 0, character = 2 },
              ['end'] = { line = 0, character = 5 },
            },
          },
        },
      }
    end,
  }

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '中文foo' })
-- 测试需要临时替换 Neovim API；LuaLS 将该受保护字段视为不可重复赋值
---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.get_clients = function() return { client } end
  local range = layers.lsp({ 1, 7, 1, 7 }, { lsp_timeout = 50 })
  vim.lsp.get_clients = old_get_clients

  ok(request_character == 2, '请求把中文后的 byte 列转换为 UTF-16 code unit')
  ok(range and vim.deep_equal(range, { 1, 7, 1, 9 }), '响应的 exclusive UTF-16 end 转为完整 foo byte 范围')
end

print('\n=== LSP selectionRange: 跨行 end.character=0 回退 ===')
do
  local layers = require('vv-expand.layers')
  local old_get_clients = vim.lsp.get_clients
  local client = {
    offset_encoding = 'utf-16',
    request_sync = function()
      return {
        result = {
          {
            range = {
              start = { line = 0, character = 0 },
              ['end'] = { line = 1, character = 0 },
            },
          },
        },
      }
    end,
  }

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'foo', 'bar' })
-- 测试需要临时替换 Neovim API；LuaLS 将该受保护字段视为不可重复赋值
---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.get_clients = function() return { client } end
  local range = layers.lsp({ 1, 2, 1, 2 }, { lsp_timeout = 50 })
  vim.lsp.get_clients = old_get_clients

  ok(range and vim.deep_equal(range, { 1, 1, 1, 3 }), '跨行 exclusive 行首回退到前一行末尾')
end

print('\n=== same-char run 配对（markdown ** / __ 嵌套，含回归）===')
do
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
