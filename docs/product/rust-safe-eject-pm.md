# Rust Safe Eject PM

## Problem And Intent

The PowerShell GUI now answers the daily question "can I unplug this SSD?" — but the *answer* still leaves the *act* of ejecting on the operating system. When Windows refuses to eject, the user sees a generic toast and has to guess which process is holding the drive. From the command line, the Rust core can list drives and read readiness, but it cannot actually eject. That makes the Rust layer permanently observational and blocks every downstream surface: scripted post-backup unmount, Tauri GUI, macOS/Linux parity.

This phase makes the Rust core authoritative for safe eject on Windows by calling CfgMgr32 directly. The promise is not "another way to eject." The promise is **"the eject either succeeds, or it tells me exactly which process is holding the drive — by name — so I can fix it in one move."**

## Target Users And Jobs

- **Power user finishing a backup pipeline.** They want a one-liner that runs after `robocopy` finishes and either ejects or refuses with a parseable reason. Today they have to alt-tab to the GUI.
- **Operator triaging a stuck eject.** When the Windows tray says "the device is currently in use," they need a *named* culprit, not a guess.
- **Future Tauri/desktop user.** They will never see this CLI, but they need a Rust core that can do the real action so the GUI can be rewritten without re-implementing platform code.

## Jobs-Caliber PM Judgment

### Essential promise

One sentence the user should say after running `stc eject E: --yes`:

> "It just ejected, and when it didn't, it told me why."

### Taste bar

The CLI is judged on three things:

1. **Truthfulness on failure.** A vetoed eject must return the veto type *and* the process name, not a generic error. If the OS gives us a `PNP_VetoOutstandingOpen` and a name, we surface both. If the OS gives us only a type, we say so.
2. **Scriptability.** Every output is JSON by default. Every failure path has a stable exit code. Stdout is the contract; stderr is for humans.
3. **Restraint.** The CLI does not kill processes. It does not stop services on its own. It does not retry forever. It surfaces the truth and exits.

### Narrative

PLAN A made the GUI honest about *whether* the user can eject. PLAN B made the Rust core honest about *what* is connected. This phase makes the Rust core honest about *acting*. After this phase, every future surface (Tauri, scripts, CI, macOS adapter) inherits the same eject contract instead of inventing one.

### Minimum lovable scope

- `stc eject <DRIVE>` with interactive confirmation by default and `--yes` for scripts.
- Native Windows CfgMgr32 path; no PowerShell shell-out for the eject itself.
- Structured veto output with veto type, veto name when available, and remediation keys that map to existing Fluent strings.
- `stc doctor --verbose` exposes Windows event-log counters (Disk 153 retries, Kernel-PnP 225 vetoes) so the readiness story has evidence behind it.
- A `command` discriminator on every CLI output so consumers know whether they got `list`, `readiness`, `doctor`, or `eject`.

### Non-Goals (sharp)

- **No Tauri GUI.** GUI consumes this contract later; not now.
- **No macOS or Linux eject implementation.** Only the trait signature and error contract are extended so the cross-platform plan stays coherent.
- **No automatic process killing.** Naming a blocker is the product. Killing it is the user's call.
- **No format-policy redesign.** Format policy is unchanged; that's a separate decision and a separate plan.
- **No replacement of the PowerShell GUI.** It keeps shipping. The CLI is additive.
- **No background daemon, no tray, no scheduled task.** This is a one-shot tool.
- **No telemetry, no network calls.** Local only.

### Tradeoffs deliberately rejected

- *"Just shell out to `Invoke-STCShellEject`."* Rejected: it inherits Shell COM's opaque failure, defeats the entire point of having a Rust core, and locks the eject path to PowerShell forever. Native CfgMgr32 is the only path that gives us veto details.
- *"Auto-stop Windows Search if it blocks."* Rejected: the GUI already gates this behind a confirmation phrase. The CLI must not be more aggressive than the GUI; it must be more *honest*.
- *"Add a `--force` that retries with backoff."* Rejected: looping doesn't fix a holding process. It only delays the user's decision.
- *"Make `eject` work without `--yes` in scripts by default."* Rejected: silent destructive defaults are how data loss happens.

## Current Reality

- Rust core (`stc-core`, `stc-cli`) is read-only. `list`, `readiness`, `doctor` all share the same observational pipeline. `doctor` and `readiness` currently return identical output (closeout follow-up).
- Real eject lives only in `src\lib\SafeEject.ps1` and goes through Shell COM, which returns an opaque `StillPresent` boolean and no veto detail.
- `windows` crate is already in workspace dependencies with `Win32_Foundation` and `Win32_Storage_FileSystem` features. CfgMgr32 needs `Win32_Devices_DeviceAndDriverInstallation` added.
- PowerShell test runners write Chinese strings to `logs/` files where Windows CP936 vs UTF-8 mismatch garbles them (closeout follow-up).
- `locales/{zh-CN,en-US}/app.ftl` already has `headline-blocked-eject-veto`. Veto-type-specific strings do not exist yet.

## Proposed Behavior

### CLI

```text
stc eject <DRIVE>            # interactive: prints summary, asks Y/N
stc eject <DRIVE> --yes      # non-interactive, scripts/CI
stc doctor                   # unchanged shape + new "command": "doctor" field
stc doctor --verbose         # adds event_counters: { disk_retry, eject_veto, global_eject_veto, window_days }
stc list                     # unchanged + new "command": "list" field
stc readiness [--drive <D>]  # unchanged + new "command": "readiness" field
```

### Output shape on successful eject

```json
{
  "command": "eject",
  "drive": "E:",
  "result": "ok",
  "still_present": false,
  "elapsed_ms": 412
}
```

### Output shape on veto

```json
{
  "command": "eject",
  "drive": "E:",
  "result": "vetoed",
  "veto_type": "PNP_VetoOutstandingOpen",
  "veto_name": "explorer.exe",
  "still_present": true,
  "remediation_keys": ["step-close-risk-apps", "step-retry-safe-eject"],
  "elapsed_ms": 380
}
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Eject succeeded, or read-only command produced output. |
| 10 | Eject vetoed (recoverable: close blocker and retry). |
| 11 | Drive letter not found or not a removable Samsung T-series drive. |
| 12 | Drive resolved but device is not ejectable (fixed/system drive misclassified). |
| 13 | Privilege required (CfgMgr32 returned access denied; rare for removable USB). |
| 20 | Internal error (FFI, unexpected NTSTATUS, JSON serialization). |
| 30 | User declined the interactive confirmation. |

## Success Criteria

- `cargo run -p stc-cli -- eject E: --yes` completes in under 3 seconds on a connected Samsung T-series drive and returns `result: "ok"` with `still_present: false`.
- When Explorer is browsing the drive root, the same command returns exit code 10, `result: "vetoed"`, `veto_name: "explorer.exe"` (or whatever name the OS reports), and `still_present: true`.
- `cargo run -p stc-cli -- doctor --verbose` returns event counters with a `window_days` field; without `--verbose`, output shape matches `readiness` plus the `command` discriminator.
- PowerShell test runners write UTF-8 logs; Chinese strings render correctly in `logs/*.log`.
- Existing PowerShell GUI behavior is unchanged. `tests/Smoke.Tests.ps1` and `tests/DailyEject.Tests.ps1` keep passing.
- `cargo fmt --check` and `cargo test` pass; new unit tests cover Ok / Vetoed / NotEjectable paths via a mock provider.

## Risks And Open Questions

- **CfgMgr32 device-instance resolution can fail on USB hubs that present multiple PDOs.** Mitigation: target the *parent* devnode of the volume's storage device, which is what the OS itself ejects.
- **Veto names are not always populated by Windows.** Some veto types (`PNP_VetoTypeUnknown`, `PNP_VetoLegacyDriver`) come without a name. Plan accepts this; output emits `veto_name: null`.
- **Live integration tests cannot run in CI without a connected Samsung drive.** Mitigation: gate Windows live tests behind `STC_LIVE_DRIVE=<letter>` env var and `#[ignore]` by default.
- **Open question (does not change the plan):** should `eject` accept a serial instead of a drive letter for stability across reconnects? Decision: defer; add to follow-ups.

## Affected Users

- **PowerShell GUI users:** no change. They keep using the GUI. Documentation gains a "scripting" section.
- **Scripters / pipeline operators:** new capability. They get a JSON contract and stable exit codes.
- **Future Tauri / cross-platform users:** unblocked. The trait now includes `eject` so macOS/Linux adapters have a target shape to implement.
