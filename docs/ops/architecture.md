# Architecture

## Decision

Samsung T-Series Console is a Windows-native PowerShell 7 + WinForms utility. It intentionally avoids Electron, Node, Python packaging, services, and installers for v1.

## Rationale

- The required data sources are native Windows surfaces: Storage cmdlets, Event Log, services, processes, Shell COM, and filesystem operations.
- The user needs a local operator tool for two known Samsung portable SSDs, not a cloud app or cross-platform product.
- PowerShell keeps the destructive operations visible and auditable, while allowing confirmation gates before formatting, service changes, or eject attempts.

## Module Boundaries

- `Logging.ps1`: JSONL runtime logging and project/log path helpers.
- `DriveDetection.ps1`: Samsung T-series disk inventory.
- `RiskAudit.ps1`: Windows event log, process, and Windows Search risk analysis.
- `ContentProfile.ps1`: recursive file mix and allocation-unit recommendation.
- `PerformanceTest.ps1`: temporary write-through benchmark.
- `FormatPolicy.ps1`: format recommendation and guarded format execution.
- `SafeEject.ps1`: flush, blocker summary, optional Search stop, Rust CfgMgr32 eject wrapper, and Shell COM fallback.
- `SamsungTConsole.ps1`: WinForms GUI and confirmation workflow.

## Safety Model

Read-only operations are the default. Non-destructive benchmark writes a temporary hidden-style test file and removes it in a `finally` block. Destructive or disruptive operations require confirmation phrases in the GUI.
