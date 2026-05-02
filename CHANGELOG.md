# Changelog

## [Unreleased]

### Added

- **Subword expansion**: word layer now expands incrementally across delimiter characters (e.g. `full` → `h-full` → `min-h-full`) instead of jumping straight to the full WORD
- **`subword_delimiters` config option**: user-configurable string of characters that trigger subword stops; defaults to `-=+/:;|,.?\!@#$%^&*~`; set to `nil` to disable and fall back to original iw → iW behavior

### Changed

- When `subword_delimiters` is set, word layer yields to pair layer after subword expansion is exhausted, instead of falling through to iW — prevents selecting across quote/bracket boundaries
