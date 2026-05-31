# Changelog

## [Unreleased]

### Added

- **Subword expansion**: word layer now expands incrementally across delimiter characters (e.g. `full` → `h-full` → `min-h-full`) instead of jumping straight to the full WORD
- **`subword_delimiters` config option**: user-configurable string of characters that trigger subword stops; defaults to `-=+/:;|,.?\!@#$%^&*~`; set to `nil` to disable and fall back to original iw → iW behavior
- **同字符成对支持连续 run 嵌套**：`pair` 层把 `**`、`__` 等连续相同分隔符识别为一个 run 并由内向外逐层嵌套，markdown 加粗 `**修复建议**` 现可逐层扩张 `修复建议` → `*修复建议*` → `**修复建议**`（此前 `**…**` 不被 `pair` 层命中，只能整体落到 treesitter）

### Changed

- When `subword_delimiters` is set, word layer yields to pair layer after subword expansion is exhausted, instead of falling through to iW — prevents selecting across quote/bracket boundaries

### Fixed

- LSP selectionRange 扩张选区右端不再少一个字符：`end.character`（0-based exclusive）直接当 1-based inclusive 用，与 treesitter 层一致（此前多减了 1）
- 含多字节字符（中文 / emoji / 带音标拉丁字母）的行上用 LSP 层扩张不再错位：请求位置与响应列都按 `client.offset_encoding`（默认 UTF-16）在字节列与 code unit 间转换，不再把 character 当字节处理
- 块可视模式（`Ctrl-V`）下按扩张 / 收缩键不再把矩形块静默转成字符可视选区：`expand` / `shrink` 入口检测到块选直接不处理，保留原选区
