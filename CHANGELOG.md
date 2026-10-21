# Changelog

## 0.2.0 - 2026-10-21

### Breaking

- setup() 不再返回配置，需要时用 get_config()

### Changed

- `subword_delimiters` 与 `keymaps.*` 各项设为 `false` 即禁用；`nil` 表示未配置、取默认值
- 移除 `VVExpandSetupOpts`，输入类型统一为 `VVExpandOpts`

## 0.1.1 - 2026-07-19

### Fixed

- 默认排除 `TelescopePrompt`、`vv-task-panel` 与 `vv-task-panel-tasks`，不再向这些 UI buffer 安装选区扩张快捷键

## 0.1.0 - 2026-07-13

### Added

- word 层支持按分隔符逐段扩张，新增 `subword_delimiters` 配置；设为 `nil` 可恢复原先的 `iw → iW` 行为，默认字符集见 README
- pair 层支持连续同字符分隔符逐层嵌套扩张，包括 Markdown 加粗标记

### Changed

- 启用 `subword_delimiters` 时，逐段扩张结束后交给 pair 层，不再通过 `iW` 跨越引号或括号边界

### Fixed

- LSP `selectionRange` 不再漏选右端字符，并按客户端编码正确处理中文、emoji 等多字节字符
- 块可视模式下扩张或收缩不再改变矩形选区
- 编辑 buffer 后收缩不再因旧选区行号越界而报错
- 手动修改选区后收缩不再恢复陈旧选区
