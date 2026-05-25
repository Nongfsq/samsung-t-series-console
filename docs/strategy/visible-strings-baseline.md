# User-Visible Strings Baseline

This is the migration baseline for Fluent keys. The current PowerShell GUI still contains hard-coded text; future Rust/Tauri surfaces should render via `locales/*/app.ftl`.

## Status

- 可以弹出 / Safe to eject
- 有风险 / Caution
- 不要直接拔 / Do not unplug
- 无法判断 / Unknown

## Actions

- 安全弹出选中硬盘 / Safely eject selected drive
- 刷新拔插状态 / Refresh eject readiness
- 处理后安全弹出选中硬盘 / Close blockers, then eject
- 查看阻塞原因 / View blockers

## Blockers

- Windows Search / SearchIndexer
- Samsung Magician
- Explorer
- Disk retry
- Eject veto
- Format mismatch

## Warnings

- Formatting destroys all data.
- Do not hard-unplug.
- If retry still fails, shut down before unplugging.
