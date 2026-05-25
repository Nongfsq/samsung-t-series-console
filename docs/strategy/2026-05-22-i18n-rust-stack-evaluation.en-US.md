# I18n, Rust Tooling, and Cross-Platform Strategy Evaluation

## Decision

The current PowerShell + WinForms implementation is a good Windows prototype and personal utility. If the goal is a distributable, maintainable, multilingual, cross-platform Samsung T-Series tool, the long-term foundation should move to Rust.

The recommended path is **Rust Core + CLI first, Tauri GUI later**. Do not rewrite the current GUI immediately. First move the stable, testable, cross-platform logic into Rust, then let the current PowerShell GUI or a future Tauri GUI call that core.

## Scorecard

| Dimension | PowerShell/WinForms | Rust CLI | Rust + Tauri GUI | Conclusion |
|---|---:|---:|---:|---|
| Windows daily eject UX | 82/100 | 72/100 | 92/100 | GUI is the daily product surface; CLI is the execution and debugging layer. |
| System control reliability | 64/100 | 88/100 | 88/100 | Rust is better suited for direct CfgMgr32, SetupAPI, and EventLog integrations. |
| Internationalization | 35/100 | 82/100 | 90/100 | Current strings are hard-coded; Fluent enables a mature locale model. |
| Cross-platform potential | 15/100 | 78/100 | 82/100 | PowerShell/WinForms is effectively Windows-only; Rust can use OS adapters. |
| Build and type safety | 45/100 | 92/100 | 88/100 | Rust compile-time checks fit a long-lived system tool. |
| Distribution | 45/100 | 86/100 | 80/100 | CLI has strong single-binary distribution; Tauri has better product UX but more packaging burden. |
| Maintenance cost | 65/100 | 84/100 | 76/100 | Rust core is worth the investment; Tauri should wait until the core stabilizes. |

Overall scores:

- Current project as a personal Windows tool: 82/100.
- Current stack as a long-term product foundation: 58/100.
- Rust Core + CLI: 86/100.
- Rust Core + Tauri GUI: 88/100.
- Immediate full Rust GUI rewrite: 70/100, not recommended.

## Technical Decision

Choose Rust Core + CLI first. Keep the existing PowerShell GUI. Rust phase one is read-only:

- `list`: detect Samsung T-series drives.
- `readiness`: print daily safe-eject readiness.
- `doctor`: print a read-only diagnostic summary.

Dangerous operations are excluded from Rust phase one: no formatting, no service stop, no eject.

## I18n Strategy

Use Fluent `.ftl` language packs:

- `locales/zh-CN/app.ftl`
- `locales/en-US/app.ftl`

Rules:

- Rust core returns structured state and message keys.
- CLI/GUI renders messages by locale.
- Statuses, actions, errors, blocker explanations, and next steps use keys.
- ICU4X can later handle dates, numbers, and list formatting.

## Cross-Platform Strategy

Platform capabilities must be implemented through OS adapters.

Windows:

- Long-term safe eject uses CfgMgr32/SetupAPI.
- Event Log, processes, and volume information remain Windows evidence.
- Rust phase one stays read-only.

macOS:

- Use Disk Arbitration API or `diskutil` fallback.
- Operate on whole disks, not only leaf partitions.
- Use `lsof` as the first blocker-analysis fallback.

Linux:

- Prefer UDisks2 D-Bus.
- CLI fallback uses `udisksctl unmount` and `udisksctl power-off`.
- Use `lsof`/`fuser` as initial blocker analysis.

## Risks

- Fully native Windows drive detection in Rust is more expensive than the current PowerShell path, so phase one allows a PowerShell metadata fallback.
- Starting Tauri too early would add UI, packaging, and multi-platform testing burden.
- Safe eject is a high-risk system operation and should wait until read-only diagnostics are stable.
- Internationalization is not string replacement; it requires structured recommendation keys.

## Next Step

Phase one creates the Rust workspace, Fluent language packs, read-only CLI, and unit tests. Phase two prototypes Windows CfgMgr32 safe eject. Phase three evaluates Tauri GUI.
