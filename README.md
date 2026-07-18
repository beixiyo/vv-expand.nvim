<div align="center">
  <h1>vv-expand.nvim</h1>

  <p><a href="./README.md">English</a> | <a href="./README.zh-CN.md">中文</a></p>

  <p>Want my Neovim configuration? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a></p>

  <p><em>Context-aware incremental selection expansion through four cascading layers: pair → LSP → treesitter → line</em></p>

  <p>
    <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&amp;logo=neovim&amp;logoColor=white" alt="Requires Neovim 0.10+" />
    <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&amp;logo=lua&amp;logoColor=white" alt="Lua" />
    <img src="https://img.shields.io/badge/zero_deps-%E2%9C%93-2ea44f?style=flat-square" alt="Zero Dependencies" />
  </p>
</div>

---

## Why This Plugin

[wildfire.nvim](https://github.com/SUSTech-data/wildfire.nvim) expands selections using only parent treesitter nodes, so it **does not understand inline visual delimiters**:

- In Markdown, with the cursor on `user` inside `` `user-picks.lua` ``, it jumps directly to the entire paragraph instead of first selecting `` `user-picks.lua` ``
- With the cursor inside `pack/init.lua` in `[pack/init.lua]`, it jumps to the entire `inline_link` node instead of first selecting `pack/init.lua`

vv-expand first performs an **inline paired-character scan** (brackets / quotes / emphasis) for fine-grained expansion, and uses treesitter only as a fallback when character-pair matching fails. LSP `selectionRange` expands by semantic structure (identifier → expression → statement → block), which is more intuitive than treesitter granularity alone. The plugin has zero runtime dependencies and automatically falls back when LSP or treesitter is unavailable

## Installation

```lua
{
  'beixiyo/vv-expand.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  ---@type VVExpandConfig
  opts = {
    pairs = {
      same = { '"', "'", '`', '*', '_', '-' },       -- Same-character pairs
      nested = {                                       -- Nested bracket pairs
        { '(', ')' }, { '[', ']' }, { '{', '}' }, { '<', '>' },
      },
    },
    layers = { 'word', 'pair', 'lsp', 'treesitter', 'line' }, -- Expansion strategy priority
    keymaps = {
      init = '<CR>',     -- Start in normal mode
      expand = '<CR>',   -- Expand in visual mode
      shrink = '<BS>',   -- Shrink in visual mode
    },
    subword_delimiters = '-=+/:;|,.?\\!@#$%^&*~', -- Segment delimiters; nil disables subword expansion
    filetype_exclude = { 'qf', 'help', 'dashboard', 'vv-explorer', 'vv-task-panel' },
    lsp_timeout = 400,   -- LSP selectionRange timeout (ms)
  },
}
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pairs.same` | `string[]` | `'"', "'", '`', '*', '_', '-'` | Same-character pairs (characters surrounded by alphanumeric characters on both sides are treated as part of a word and are not paired) |
| `pairs.nested` | `string[][]` | `() [] {} <>` | Nested bracket pairs matched with a stack |
| `layers` | `string[]` | `{ 'word', 'pair', 'lsp', 'treesitter', 'line' }` | Expansion strategy priority; remove a layer from the list to disable it |
| `keymaps.init` | `string` | `'<CR>'` | Start a selection in normal mode |
| `keymaps.expand` | `string` | `'<CR>'` | Expand the selection outward by one level in visual mode |
| `keymaps.shrink` | `string` | `'<BS>'` | Shrink the selection inward by one level in visual mode |
| `filetype_exclude` | `string[]` | `{ 'qf', 'help', ... }` | Filetypes excluded from keymap bindings |
| `subword_delimiters` | `string?` | `'-=+/:;\|,.?\\!@#$%^&*~'` | Characters used as delimiters for segment-by-segment expansion; `nil` disables it and expands directly from `iw` to `iW` |
| `lsp_timeout` | `integer` | `400` | Timeout in milliseconds for LSP `selectionRange` requests |
