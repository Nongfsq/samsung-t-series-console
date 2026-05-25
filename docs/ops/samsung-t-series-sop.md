# Samsung T-Series Operating SOP

## Daily Safe Eject

1. Connect the SSD directly to the rear motherboard USB-C/SS20 port where possible.
2. Open Samsung T-Series Console.
3. Stay on the **Daily Eject** tab.
4. Read the status card for the drive you want to unplug.
5. If the card says it is safe or only cautionary, click **安全弹出选中硬盘**.
6. If the card says not to unplug, close the listed blockers or shut Windows down before disconnecting.

## Diagnostic Use

Use **Diagnostics & Repair** only when the drive was unplugged unsafely, slowed down, failed to eject, had firmware or cable changes, or needs format-policy review.

## System Policy Maintenance

Use **Apply Policies** after plugging in a Samsung T7/T7 Shield/T9 if Windows assigns a new drive letter. It scans currently connected Samsung T-series USB drives and excludes their current roots from Windows Search.

Run the console as administrator when applying Samsung Magician policy. Windows requires elevation to change `SamsungMagicianSVC` startup type and to stop the current running service instance.

## Format Policy

- T7 Shield 4TB used for Sony RAW, video, ISO, and other large assets: `exFAT + 256KB`.
- T7 1TB mixed-use disk: keep `exFAT + 128KB` unless content profiling shows large-file-dominant usage or performance/audit results indicate a problem.
- Do not format a drive unless its data is backed up and verified.

## When Safe Eject Fails

Common blockers are Explorer, Samsung Magician, thumbnail generation, and applications with open files. Windows Search is also a blocker if the drive root is not excluded from indexing. The daily eject button now prefers the Rust CfgMgr32 eject path so a Windows veto can be surfaced as structured evidence. If Safe Eject Assistant cannot eject the disk cleanly, the safest fallback is shutting Windows down and unplugging after power-off.
