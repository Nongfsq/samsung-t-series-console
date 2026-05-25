# Daily Safe Eject PM

## Problem And Intent

The first version of Samsung T-Series Console is a useful diagnostics tool, but everyday unplugging should not require running a full six-step investigation. The product needs a default daily mode that answers one question quickly: can this drive be safely ejected right now?

## Product Score

- Current product experience: 72/100.
- Target product experience: 90/100.
- Main gap: the current UI exposes technical objects and diagnostic steps before it gives a daily decision.

## Target Job

Before unplugging a Samsung T7/T7 Shield/T9, the user opens the tool and expects a clear decision within 10 seconds:

- safe to eject,
- close or stop these blockers first,
- or do not unplug; shut down first if eject keeps failing.

## PM Judgment

The product promise is not "six powerful tools." The promise is "I can unplug this SSD without corrupting exFAT again." Daily safety must be the default story; deep diagnostics must stay available but secondary.

## Proposed Behavior

- Default screen is Daily Eject Dashboard.
- Each connected Samsung T-series drive gets a readable status card.
- Main action is Safe Eject Selected Drive.
- Advanced diagnostics keep the original six-step workflow.
- Format remains possible but is treated as a dangerous advanced repair path.

## Success Criteria

- Opening the app automatically shows connected drives.
- Daily dashboard avoids content scans, benchmarking, or recursive work.
- The user sees plain-language blockers such as Windows Search or Samsung Magician.
- Raw event data and JSON are available only in details/logs.
- The tool never formats, stops services, or ejects without explicit confirmation.

## Non-Goals

- No Electron rewrite.
- No background resident tray app in this iteration.
- No automatic process killing.
- No automatic formatting based only on heuristics.
- No macOS GUI in this iteration.
