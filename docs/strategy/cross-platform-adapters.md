# Cross-Platform Adapter Design

## Contract

Each OS adapter must eventually implement:

- list removable Samsung T-series drives,
- compute read-only readiness evidence,
- identify likely blockers,
- perform safe eject only after explicit confirmation,
- return structured success, failure, and veto information.

## Windows

Read-only phase:

- Enumerate removable drive letters.
- Read label, filesystem, allocation unit, size, and free space.
- Use PowerShell metadata fallback for model, serial, and disk number.
- Detect common blockers: Windows Search and Samsung Magician.

Eject phase:

- Native Windows eject is implemented through Rust CfgMgr32. The PowerShell GUI prefers that path and keeps Shell COM as a fallback.
- Return veto type/name where available.
- Keep destructive or disruptive operations behind confirmation.

## macOS

Read-only phase:

- Identify external disks through Disk Arbitration or `diskutil list -plist`.
- Map volumes to whole disk identifiers.
- Read filesystem, capacity, and mount state.

Future eject phase:

- Unmount whole disk before eject.
- Use Disk Arbitration API when possible.
- `diskutil unmountDisk` and `diskutil eject` can be fallback commands.
- Use `lsof` to explain blockers.

## Linux

Read-only phase:

- Identify removable USB block devices through UDisks2 or `/sys`.
- Map filesystems and mountpoints.
- Read label, filesystem, size, and mount state.

Future eject phase:

- Prefer UDisks2 D-Bus.
- Fallback to `udisksctl unmount` and `udisksctl power-off`.
- Use `lsof` or `fuser` to explain blockers.

## Non-Goals For Phase One

- No cross-platform eject.
- No formatting.
- No service control.
- No auto-kill process behavior.
