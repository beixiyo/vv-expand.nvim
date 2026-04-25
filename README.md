# vv-expand.nvim

智能增量选区：按 `<CR>` 逐级扩大选区，`<BS>` 逐级回缩。按 **pair → LSP → treesitter → line** 四层优先级级联，无依赖

## 为什么不用 wildfire

[wildfire.nvim](https://github.com/SUSTech-data/wildfire.nvim) 只基于 treesitter 父节点扩张。**treesitter 节点是按语法结构切的，不理解行内视觉分隔符**，常见问题：

- Markdown 文本段落里光标在 `` `user-picks.lua` `` 的 `user` 上，按 `<CR>` 直接跳到整段 paragraph，不会先选 `user-picks.lua` 再选 `` `user-picks.lua` ``
- `[pack/init.lua]` 内部光标，wildfire 也不先选 `pack/init.lua` 再选 `[pack/init.lua]`，而是跳到整个 `inline_link` 节点
- wildfire 的 `surrounds` 配置只能在节点边界恰好是成对字符时生效，大多数真实代码/文档场景命中不到

vv-expand 先用**行内成对字符扫描**（括号/引号/emphasis）做细粒度扩张，treesitter 只作为字符对失败后的补充层。在 markdown 等文本场景下差别明显；在代码场景下（成对字符大多由 TS 节点精确覆盖）行为与 wildfire 基本一致

## 扩张逻辑

每次按 `<CR>`，按 [layers.lua](lua/vv-expand/layers.lua) 中配置的顺序尝试下列策略，第一个**严格包含当前选区**的结果即为下一级：

### 1. pair —— 本行成对字符

- **同字符对**：`"` `'` `` ` `` `*` `_` `-`。左到右两两配对，每对产出"内部"（不含字符本身）和"外部"（含字符）两个候选，按最内层选择
- **嵌套括号对**：`()` `[]` `{}` `<>`。基于栈匹配，支持嵌套
- **词边界规则**：同字符两侧同时为 ASCII 字母/数字时视为词内（如 `snake_case` 的 `_`、`foo-bar` 的 `-`），**不参与配对**。避免 kebab-case 标识符把列表标号 `-` 和变量名里的 `-` 错配成一对

本层仅在单行内生效；跨行选区直接跳过

### 2. LSP —— `textDocument/selectionRange`

attach 了支持 `selectionRange` 方法的 LSP 时生效。用 `request_sync` 超时 400ms；从返回的链路往上找第一个严格包含当前选区的 range

LSP 理解语义结构：标识符 → 表达式 → 语句 → 块 → 函数，比 treesitter 粒度更贴近"语义单位"

### 3. treesitter —— 语法父节点

有 parser 时从当前选区起点的最深节点往上走，第一个严格包含当前选区的节点即为目标。覆盖代码块、段落、节等结构性单位

### 4. line —— 行扩张兜底

没有 pair/LSP/TS 可用时：当前非整行 → 选成整行；已是整行 → 上下各扩一行。**总能成功**（除非已到整个 buffer），保证按 `<CR>` 永远有反应

## 使用

```
n:<CR>    开始选区 / 向外扩一级
x:<CR>    继续向外扩一级
x:<BS>    向内回缩一级
```

按键 buffer-local 绑定；excluded filetype 下不绑定

## 安装

lazy.nvim：

```lua
{
  'beixiyo/vv-expand.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {},
}
```

## 默认配置

```lua
require("vv-expand").setup({
  pairs = {
    same = { '"', "'", '`', '*', '_', '-' },
    nested = {
      { '(', ')' }, { '[', ']' }, { '{', '}' }, { '<', '>' },
    },
  },
  layers = { 'pair', 'lsp', 'treesitter', 'line' },
  keymaps = {
    init = '<CR>',    -- normal 模式起手
    expand = '<CR>',  -- visual 模式扩张
    shrink = '<BS>',  -- visual 模式回缩
  },
  filetype_exclude = { 'qf', 'help', 'dashboard', 'vv-explorer', 'vv-task-panel' },
  lsp_timeout = 400,
})
```

- `layers` 列表顺序 = 优先级；想让 LSP 总比 pair 先试，调成 `{ 'lsp', 'pair', 'treesitter', 'line' }`
- 想彻底关掉某层，从列表里删掉即可
- `pairs.same` 里去掉 `-` 就避免 em-dash / 列表场景下的潜在误伤（默认靠词边界规则已能避免大多数情况）

## 模块结构

| 文件 | 职责 |
|---|---|
| [init.lua](lua/vv-expand/init.lua) | 入口：config、public API、keymap、autocmd |
| [range.lua](lua/vv-expand/range.lua) | 范围运算 + UTF-8 字符边界 + visual 读写 |
| [layers.lua](lua/vv-expand/layers.lua) | 四层扩张策略实现 |

### 关于 UTF-8 字符边界

`nvim_win_set_cursor` 要求 col 落在字符首字节上；落在 multi-byte 字符的 continuation byte 时 nvim 会静默回退到字符首字节，导致 `set_visual` 想设的 end col 和 `getpos("'>")` 回读的 col 错位

表现：选中含 CJK / emoji 的行后继续按 `<CR>`，treesitter 每次都返回一个"严格包含"当前选区的 range，set_visual 每次又被 nvim 回退到同一个位置，**视觉上毫无变化**，像卡住

[range.lua](lua/vv-expand/range.lua) 的处理：
- `to_char_start(lnum, col)` —— 落点规整到字符首字节，用于 `set_visual` 写入
- `to_char_end(lnum, col)` —— 落点规整到字符末字节，用于 `get_cur` 读回

这样栈里存的 range 和实际 visual 的范围始终一致，不会出现 "expand 了但看起来没动"

## 无依赖

零运行时依赖。LSP / treesitter parser 缺失时自动降级到下一层

## Testing

Smoke test (zero deps, runs in `-u NONE`):

```bash
nvim --headless -u NONE -l tests/test_smoke.lua
```

Expected: trailing line `X passed, 0 failed`.
