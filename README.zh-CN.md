<div align="center">
  <h1>vv-expand.nvim</h1>

  <p><a href="./README.md">English</a> | <a href="./README.zh-CN.md">中文</a></p>

  <p>想要我的 Neovim 配置？查看 <a href="https://github.com/beixiyo/dotfiles">dotfiles</a></p>

  <p><em>智能增量选区 — 按 pair → LSP → treesitter → line 四层级联扩张</em></p>

  <p>
    <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&amp;logo=neovim&amp;logoColor=white" alt="需要 Neovim 0.10+" />
    <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&amp;logo=lua&amp;logoColor=white" alt="Lua" />
    <img src="https://img.shields.io/badge/zero_deps-%E2%9C%93-2ea44f?style=flat-square" alt="零依赖" />
  </p>
</div>

---

## 为什么要这个插件

[wildfire.nvim](https://github.com/SUSTech-data/wildfire.nvim) 只基于 treesitter 父节点扩张，**不理解行内视觉分隔符**：

- Markdown 里光标在 `` `user-picks.lua` `` 的 `user` 上 → 直接跳到整段 paragraph，不会先选 `` `user-picks.lua` ``
- `[pack/init.lua]` 内部光标 → 跳到整个 `inline_link` 节点，不会先选 `pack/init.lua`

vv-expand 先用**行内成对字符扫描**（括号 / 引号 / emphasis）做细粒度扩张，treesitter 只作为字符对失败后的补充层；LSP `selectionRange` 按语义结构扩张（标识符 → 表达式 → 语句 → 块），比纯 TS 粒度更贴近直觉。零运行时依赖，LSP / treesitter 缺失时自动降级

## 安装

```lua
{
  'beixiyo/vv-expand.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  ---@type ExpandConfig
  opts = {
    pairs = {
      same = { '"', "'", '`', '*', '_', '-' },       -- 同字符配对
      nested = {                                       -- 嵌套括号对
        { '(', ')' }, { '[', ']' }, { '{', '}' }, { '<', '>' },
      },
    },
    layers = { 'word', 'pair', 'lsp', 'treesitter', 'line' }, -- 扩张策略优先级
    keymaps = {
      init = '<CR>',     -- normal 模式起手
      expand = '<CR>',   -- visual 模式扩张
      shrink = '<BS>',   -- visual 模式回缩
    },
    subword_delimiters = '-=+/:;|,.?\\!@#$%^&*~', -- 逐段扩张分隔符；nil 则禁用
    filetype_exclude = { 'qf', 'help', 'dashboard', 'vv-explorer', 'vv-task-panel' },
    lsp_timeout = 400,   -- LSP selectionRange 超时（ms）
  },
}
```

## 配置

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `pairs.same` | `string[]` | `'"', "'", '`', '*', '_', '-'` | 同字符配对列表（两侧同为字母数字时视为词内，不配对） |
| `pairs.nested` | `string[][]` | `() [] {} <>` | 嵌套括号对，基于栈匹配 |
| `layers` | `string[]` | `{ 'word', 'pair', 'lsp', 'treesitter', 'line' }` | 扩张策略优先级；想关掉某层从列表删除即可 |
| `keymaps.init` | `string` | `'<CR>'` | normal 模式开始选区 |
| `keymaps.expand` | `string` | `'<CR>'` | visual 模式向外扩一级 |
| `keymaps.shrink` | `string` | `'<BS>'` | visual 模式向内缩一级 |
| `filetype_exclude` | `string[]` | `{ 'qf', 'help', ... }` | 排除的 filetype，不绑定按键 |
| `subword_delimiters` | `string?` | `'-=+/:;\|,.?\\!@#$%^&*~'` | 逐段扩张的分隔符字符集；`nil` 则禁用逐段扩张，直接 iw → iW |
| `lsp_timeout` | `integer` | `400` | LSP `selectionRange` 请求超时 ms |
