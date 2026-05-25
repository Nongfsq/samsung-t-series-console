use crate::model::{Blocker, Drive, EjectOutcome, EventCounters};

#[derive(Debug, thiserror::Error)]
pub enum PlatformError {
    #[error("platform operation failed: {0}")]
    Operation(String),
    #[error("unsupported on this platform: {0}")]
    Unsupported(&'static str),
    #[error("drive not found: {0}")]
    DriveNotFound(String),
    #[error("device is not ejectable: {0}")]
    NotEjectable(String),
    #[error("access denied (try elevated shell)")]
    AccessDenied,
}

pub trait PlatformDriveProvider {
    fn list_drives(&self) -> Result<Vec<Drive>, PlatformError>;
    fn current_blockers(&self, _drive: &Drive) -> Result<Vec<Blocker>, PlatformError> {
        Ok(Vec::new())
    }
    fn event_counters(
        &self,
        _drive: &Drive,
        window_days: u32,
    ) -> Result<EventCounters, PlatformError> {
        Ok(EventCounters {
            critical_disk_retry: 0,
            historical_disk_retry: 0,
            eject_veto: 0,
            global_eject_veto: 0,
            window_days,
            critical_minutes: 30,
        })
    }
    fn eject(&self, _drive: &Drive) -> Result<EjectOutcome, PlatformError> {
        Err(PlatformError::Unsupported(
            "eject not implemented for this platform",
        ))
    }
}

#[derive(Debug, Default)]
pub struct SystemDriveProvider;

impl PlatformDriveProvider for SystemDriveProvider {
    fn list_drives(&self) -> Result<Vec<Drive>, PlatformError> {
        platform_list_drives()
    }

    fn current_blockers(&self, _drive: &Drive) -> Result<Vec<Blocker>, PlatformError> {
        platform_current_blockers(_drive)
    }

    fn event_counters(
        &self,
        drive: &Drive,
        window_days: u32,
    ) -> Result<EventCounters, PlatformError> {
        platform_event_counters(drive, window_days)
    }

    fn eject(&self, drive: &Drive) -> Result<EjectOutcome, PlatformError> {
        platform_eject(drive)
    }
}

#[cfg(windows)]
fn platform_list_drives() -> Result<Vec<Drive>, PlatformError> {
    windows_impl::list_drives()
}

#[cfg(not(windows))]
fn platform_list_drives() -> Result<Vec<Drive>, PlatformError> {
    Ok(Vec::new())
}

#[cfg(windows)]
fn platform_current_blockers(drive: &Drive) -> Result<Vec<Blocker>, PlatformError> {
    Ok(windows_impl::current_blockers(drive))
}

#[cfg(not(windows))]
fn platform_current_blockers(_drive: &Drive) -> Result<Vec<Blocker>, PlatformError> {
    Ok(Vec::new())
}

#[cfg(windows)]
fn platform_event_counters(
    drive: &Drive,
    window_days: u32,
) -> Result<EventCounters, PlatformError> {
    windows_impl::event_counters(drive, window_days)
}

#[cfg(not(windows))]
fn platform_event_counters(
    _drive: &Drive,
    window_days: u32,
) -> Result<EventCounters, PlatformError> {
    Ok(EventCounters {
        critical_disk_retry: 0,
        historical_disk_retry: 0,
        eject_veto: 0,
        global_eject_veto: 0,
        window_days,
        critical_minutes: 30,
    })
}

#[cfg(windows)]
fn platform_eject(drive: &Drive) -> Result<EjectOutcome, PlatformError> {
    windows_impl::eject(drive)
}

#[cfg(not(windows))]
fn platform_eject(_drive: &Drive) -> Result<EjectOutcome, PlatformError> {
    Err(PlatformError::Unsupported(
        "eject not implemented for this platform",
    ))
}

#[cfg(windows)]
fn is_process_running(process_name: &str) -> bool {
    let script = format!(
        "$p = Get-Process -Name '{}' -ErrorAction SilentlyContinue; if ($p) {{ 'true' }} else {{ 'false' }}",
        process_name
    );
    std::process::Command::new("powershell")
        .args(["-NoProfile", "-Command", &script])
        .output()
        .map(|output| String::from_utf8_lossy(&output.stdout).contains("true"))
        .unwrap_or(false)
}

fn drive_letter(drive: &str) -> Option<char> {
    let mut chars = drive.chars();
    let letter = chars.next()?.to_ascii_uppercase();
    if letter.is_ascii_alphabetic() {
        Some(letter)
    } else {
        None
    }
}

#[cfg(windows)]
mod windows_impl {
    use super::{PlatformError, drive_letter};
    use crate::model::{Blocker, BlockerKind, Drive, EjectOutcome, EventCounters, VetoType};
    use std::collections::HashMap;
    use std::thread;
    use std::time::{Duration, Instant};
    use windows::Win32::Storage::FileSystem::{
        GetDiskFreeSpaceExW, GetDiskFreeSpaceW, GetDriveTypeW, GetLogicalDrives,
        GetVolumeInformationW,
    };
    use windows::core::PCWSTR;
    use windows_sys::Win32::Devices::DeviceAndDriverInstallation::{
        CM_Get_Device_IDW, CM_Get_Parent, CM_LOCATE_DEVNODE_NORMAL, CM_Locate_DevNodeW,
        CM_Request_Device_EjectW, CR_ACCESS_DENIED, CR_INVALID_DEVNODE, CR_NO_SUCH_DEVNODE,
        CR_REMOVE_VETOED, CR_SUCCESS, PNP_VETO_TYPE, PNP_VetoAlreadyRemoved, PNP_VetoDevice,
        PNP_VetoDriver, PNP_VetoIllegalDeviceRequest, PNP_VetoInsufficientPower,
        PNP_VetoInsufficientRights, PNP_VetoLegacyDevice, PNP_VetoLegacyDriver,
        PNP_VetoNonDisableable, PNP_VetoOutstandingOpen, PNP_VetoPendingClose, PNP_VetoTypeUnknown,
        PNP_VetoWindowsApp, PNP_VetoWindowsService,
    };

    const DRIVE_REMOVABLE_VALUE: u32 = 2;

    #[derive(Debug, Default, serde::Deserialize)]
    struct EjectVetoEvent {
        process_name: Option<String>,
        process_id: Option<u32>,
        command_line: Option<String>,
        affected_device: Option<String>,
    }

    pub fn current_blockers(drive: &Drive) -> Vec<Blocker> {
        let mut blockers = Vec::new();
        if let Some(service) = samsung_magician_service_status() {
            if service.eq_ignore_ascii_case("running") {
                blockers.push(Blocker {
                    kind: BlockerKind::SamsungMagician,
                    process_name: Some("SamsungMagicianSVC".to_string()),
                    pid: None,
                    message_key: "blocker-samsung-magician".to_string(),
                });
            }
        }

        for name in ["SamsungMagician", "SamsungPortableSSD"] {
            if super::is_process_running(name) {
                blockers.push(Blocker {
                    kind: BlockerKind::SamsungMagician,
                    process_name: Some(name.to_string()),
                    pid: None,
                    message_key: "blocker-samsung-magician".to_string(),
                });
            }
        }

        if super::is_process_running("SearchIndexer")
            && drive_letter(&drive.drive)
                .map(|letter| !windows_search_excludes_drive(letter))
                .unwrap_or(true)
        {
            blockers.push(Blocker {
                kind: BlockerKind::SearchIndexer,
                process_name: Some("SearchIndexer".to_string()),
                pid: None,
                message_key: "blocker-search-indexer".to_string(),
            });
        }

        blockers
    }

    pub fn list_drives() -> Result<Vec<Drive>, PlatformError> {
        let mut ps_metadata = powershell_usb_disk_metadata();
        if !ps_metadata.is_empty() {
            let mut drives = Vec::new();
            for (letter, meta) in ps_metadata.drain() {
                let root = format!("{letter}:\\");
                let info = volume_info(&root);
                let free = free_space(&root);
                let allocation_unit_kb = allocation_unit_kb(&root);
                let model = meta.model.unwrap_or_else(|| "USB Drive".to_string());
                if !is_samsung_t_series(&model) {
                    continue;
                }
                drives.push(Drive {
                    drive: format!("{letter}:"),
                    label: info.label,
                    model,
                    serial: meta.serial,
                    file_system: info.file_system,
                    allocation_unit_kb,
                    size_gb: free.map(|(_, total)| total / 1024 / 1024 / 1024),
                    free_gb: free.map(|(free, _)| free / 1024 / 1024 / 1024),
                    disk_number: meta.disk_number,
                    is_samsung_t_series: true,
                });
            }
            drives.sort_by(|a, b| a.drive.cmp(&b.drive));
            return Ok(drives);
        }

        let mask = unsafe { GetLogicalDrives() };
        if mask == 0 {
            return Err(PlatformError::Operation(
                "GetLogicalDrives returned 0".to_string(),
            ));
        }

        let mut drives = Vec::new();
        for index in 0..26 {
            if mask & (1 << index) == 0 {
                continue;
            }
            let letter = (b'A' + index as u8) as char;
            let root = format!("{letter}:\\");
            let root_w = wide(&root);
            let drive_type = unsafe { GetDriveTypeW(PCWSTR(root_w.as_ptr())) };
            if drive_type != DRIVE_REMOVABLE_VALUE {
                continue;
            }

            let info = volume_info(&root);
            let free = free_space(&root);
            let allocation_unit_kb = allocation_unit_kb(&root);
            let meta = ps_metadata.remove(&letter.to_string());
            let model = meta
                .as_ref()
                .and_then(|m| m.model.clone())
                .unwrap_or_else(|| "Removable Drive".to_string());
            let serial = meta.as_ref().and_then(|m| m.serial.clone());
            let is_samsung = is_samsung_t_series(&model);
            if !is_samsung {
                continue;
            }

            drives.push(Drive {
                drive: format!("{letter}:"),
                label: info.label,
                model,
                serial,
                file_system: info.file_system,
                allocation_unit_kb,
                size_gb: free.map(|(_, total)| total / 1024 / 1024 / 1024),
                free_gb: free.map(|(free, _)| free / 1024 / 1024 / 1024),
                disk_number: meta.and_then(|m| m.disk_number),
                is_samsung_t_series: true,
            });
        }

        Ok(drives)
    }

    pub fn event_counters(drive: &Drive, window_days: u32) -> Result<EventCounters, PlatformError> {
        let disk_number = drive.disk_number.map(|n| n.to_string()).unwrap_or_default();
        let drive_letter = drive_letter(&drive.drive).unwrap_or_default().to_string();
        let serial = drive.serial.clone().unwrap_or_default();
        let critical_minutes = 30u32;
        let script = format!(
            r#"
$start = (Get-Date).AddDays(-1 * {window_days})
$criticalStart = (Get-Date).AddMinutes(-1 * {critical_minutes})
$events = @(Get-WinEvent -FilterHashtable @{{ LogName = 'System'; Id = 153,225; StartTime = $start }} -ErrorAction SilentlyContinue)
$diskRetryAll = @($events | Where-Object {{ $_.ProviderName -eq 'disk' -and $_.Id -eq 153 -and $_.Message -match [regex]::Escape('Disk {disk_number}') }})
$criticalDiskRetry = @($diskRetryAll | Where-Object {{ $_.TimeCreated -ge $criticalStart }}).Count
$ejectVeto = @($events | Where-Object {{ $_.Id -eq 225 -and (($_.Message -match [regex]::Escape('{drive_letter}:')) -or ('{serial}' -and $_.Message -match [regex]::Escape('{serial}'))) }}).Count
$globalEjectVeto = @($events | Where-Object {{ $_.Id -eq 225 -and $_.Message -match '(?i)SearchIndexer|explorer|Samsung' }}).Count
[pscustomobject]@{{ critical_disk_retry = $criticalDiskRetry; historical_disk_retry = $diskRetryAll.Count; eject_veto = $ejectVeto; global_eject_veto = $globalEjectVeto; window_days = {window_days}; critical_minutes = {critical_minutes} }} | ConvertTo-Json -Compress
"#
        );
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .output()
            .map_err(|err| PlatformError::Operation(err.to_string()))?;
        let text = String::from_utf8_lossy(&output.stdout);
        serde_json::from_str(text.trim()).map_err(|err| PlatformError::Operation(err.to_string()))
    }

    fn samsung_magician_service_status() -> Option<String> {
        let script = "(Get-Service -Name SamsungMagicianSVC -ErrorAction SilentlyContinue).Status";
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", script])
            .output()
            .ok()?;
        let status = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if status.is_empty() {
            None
        } else {
            Some(status)
        }
    }

    fn recent_veto_event(letter: char) -> Option<EjectVetoEvent> {
        let script = format!(
            r#"
$event = Get-WinEvent -FilterHashtable @{{ LogName = 'System'; Id = 225; StartTime = (Get-Date).AddMinutes(-2) }} -ErrorAction SilentlyContinue |
  Where-Object {{ $_.Message.Contains('USB\VID_04E8') -or $_.Message.Contains('{letter}:') }} |
  Sort-Object TimeCreated -Descending |
  Select-Object -First 1
if (-not $event) {{ return }}
$message = [string]$event.Message
$processName = $null
$processId = $null
$commandLine = $null
$affectedDevice = $null
$lines = @($message -split "`r?`n" | Where-Object {{ -not [string]::IsNullOrWhiteSpace($_) }})
$first = if ($lines.Count -gt 0) {{ $lines[0] }} else {{ '' }}
$appMatch = [regex]::Match($first, 'The application (.+?) with process id')
$pidMatch = [regex]::Match($first, 'with process id (\d+) stopped')
$processPath = if ($appMatch.Success) {{ $appMatch.Groups[1].Value }} else {{ $null }}
if ($processPath) {{ $processName = Split-Path -Leaf $processPath }}
if ($pidMatch.Success) {{ $processId = [int]$pidMatch.Groups[1].Value }}
$commandLine = (($lines | Where-Object {{ $_ -like 'Process command line:*' }} | Select-Object -First 1) -replace '^Process command line:\s*','')
if ([string]::IsNullOrWhiteSpace($commandLine)) {{ $commandLine = $null }}
$affectedDevice = $lines | Where-Object {{ $_ -match '^(STORAGE|USB|SCSI)\\' }} | Select-Object -Last 1
[pscustomobject]@{{
  process_name = $processName
  process_id = $processId
  command_line = $commandLine
  affected_device = $affectedDevice
}} | ConvertTo-Json -Compress
"#
        );
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .output()
            .ok()?;
        let text = String::from_utf8_lossy(&output.stdout);
        if text.trim().is_empty() {
            return None;
        }
        serde_json::from_str(text.trim()).ok()
    }

    pub fn eject(drive: &Drive) -> Result<EjectOutcome, PlatformError> {
        let start = Instant::now();
        let letter = drive_letter(&drive.drive)
            .ok_or_else(|| PlatformError::DriveNotFound(drive.drive.clone()))?;
        let disk_id = disk_device_id(drive)?;
        let disk_devinst = locate_devinst(&disk_id)?;
        let devinst = eject_devinst_for_disk(disk_devinst).unwrap_or(disk_devinst);

        let mut veto_type: PNP_VETO_TYPE = PNP_VetoTypeUnknown;
        let mut veto_name = vec![0u16; 1024];
        let cr = unsafe {
            CM_Request_Device_EjectW(
                devinst,
                &mut veto_type,
                veto_name.as_mut_ptr(),
                veto_name.len() as u32,
                0,
            )
        };
        let elapsed_ms = start.elapsed().as_millis() as u64;
        match cr {
            CR_SUCCESS => Ok(EjectOutcome::Ok {
                drive: drive.drive.clone(),
                still_present: drive_still_present_after_eject(letter),
                elapsed_ms,
            }),
            CR_REMOVE_VETOED => {
                let event = recent_veto_event(letter);
                let remediation_keys = remediation_keys(veto_type, event.as_ref());
                Ok(EjectOutcome::Vetoed {
                    drive: drive.drive.clone(),
                    veto_type: map_veto_type(veto_type),
                    veto_name: non_empty_wide(&veto_name),
                    veto_process_name: event.as_ref().and_then(|e| e.process_name.clone()),
                    veto_process_id: event.as_ref().and_then(|e| e.process_id),
                    veto_process_command_line: event.as_ref().and_then(|e| e.command_line.clone()),
                    affected_device: event.as_ref().and_then(|e| e.affected_device.clone()),
                    still_present: drive_still_present(letter),
                    remediation_keys,
                    elapsed_ms,
                })
            }
            CR_INVALID_DEVNODE | CR_NO_SUCH_DEVNODE => {
                if let Some(parent) = parent_devinst(devinst)? {
                    request_eject_parent(drive, letter, parent, start)
                } else {
                    Ok(EjectOutcome::NotEjectable {
                        drive: drive.drive.clone(),
                        reason_key: "eject-not-ejectable".to_string(),
                        elapsed_ms,
                    })
                }
            }
            CR_ACCESS_DENIED => Err(PlatformError::AccessDenied),
            other => Err(map_configret(
                other,
                format!("CM_Request_Device_EjectW({disk_id})"),
            )),
        }
    }

    fn request_eject_parent(
        drive: &Drive,
        letter: char,
        devinst: u32,
        start: Instant,
    ) -> Result<EjectOutcome, PlatformError> {
        let mut veto_type: PNP_VETO_TYPE = PNP_VetoTypeUnknown;
        let mut veto_name = vec![0u16; 1024];
        let cr = unsafe {
            CM_Request_Device_EjectW(
                devinst,
                &mut veto_type,
                veto_name.as_mut_ptr(),
                veto_name.len() as u32,
                0,
            )
        };
        let elapsed_ms = start.elapsed().as_millis() as u64;
        match cr {
            CR_SUCCESS => Ok(EjectOutcome::Ok {
                drive: drive.drive.clone(),
                still_present: drive_still_present_after_eject(letter),
                elapsed_ms,
            }),
            CR_REMOVE_VETOED => {
                let event = recent_veto_event(letter);
                let remediation_keys = remediation_keys(veto_type, event.as_ref());
                Ok(EjectOutcome::Vetoed {
                    drive: drive.drive.clone(),
                    veto_type: map_veto_type(veto_type),
                    veto_name: non_empty_wide(&veto_name),
                    veto_process_name: event.as_ref().and_then(|e| e.process_name.clone()),
                    veto_process_id: event.as_ref().and_then(|e| e.process_id),
                    veto_process_command_line: event.as_ref().and_then(|e| e.command_line.clone()),
                    affected_device: event.as_ref().and_then(|e| e.affected_device.clone()),
                    still_present: drive_still_present(letter),
                    remediation_keys,
                    elapsed_ms,
                })
            }
            CR_ACCESS_DENIED => Err(PlatformError::AccessDenied),
            other => Err(map_configret(
                other,
                "CM_Request_Device_EjectW(parent)".to_string(),
            )),
        }
    }

    fn is_samsung_t_series(model: &str) -> bool {
        let lower = model.to_ascii_lowercase();
        lower.contains("samsung pssd")
            || lower.contains("pssd t7")
            || lower.contains("pssd t9")
            || lower.contains("t7 shield")
    }

    #[derive(Default)]
    struct VolumeInfo {
        label: Option<String>,
        file_system: Option<String>,
    }

    fn volume_info(root: &str) -> VolumeInfo {
        let root_w = wide(root);
        let mut label = vec![0u16; 260];
        let mut fs = vec![0u16; 260];
        let ok = unsafe {
            GetVolumeInformationW(
                PCWSTR(root_w.as_ptr()),
                Some(&mut label),
                None,
                None,
                None,
                Some(&mut fs),
            )
        }
        .is_ok();

        if !ok {
            return VolumeInfo::default();
        }

        VolumeInfo {
            label: Some(from_wide_z(&label)),
            file_system: Some(from_wide_z(&fs)),
        }
    }

    fn free_space(root: &str) -> Option<(u64, u64)> {
        let root_w = wide(root);
        let mut free_available = 0u64;
        let mut total = 0u64;
        let mut total_free = 0u64;
        unsafe {
            GetDiskFreeSpaceExW(
                PCWSTR(root_w.as_ptr()),
                Some(&mut free_available),
                Some(&mut total),
                Some(&mut total_free),
            )
        }
        .ok()?;
        Some((free_available, total))
    }

    fn allocation_unit_kb(root: &str) -> Option<u64> {
        let root_w = wide(root);
        let mut sectors_per_cluster = 0u32;
        let mut bytes_per_sector = 0u32;
        let mut free_clusters = 0u32;
        let mut clusters = 0u32;
        unsafe {
            GetDiskFreeSpaceW(
                PCWSTR(root_w.as_ptr()),
                Some(&mut sectors_per_cluster),
                Some(&mut bytes_per_sector),
                Some(&mut free_clusters),
                Some(&mut clusters),
            )
        }
        .ok()?;
        Some((sectors_per_cluster as u64 * bytes_per_sector as u64) / 1024)
    }

    #[derive(Default)]
    struct PsMeta {
        model: Option<String>,
        serial: Option<String>,
        disk_number: Option<u32>,
    }

    fn powershell_usb_disk_metadata() -> HashMap<String, PsMeta> {
        let script = r#"
$items = @()
Get-Disk | Where-Object { $_.BusType -eq 'USB' } | ForEach-Object {
  $disk = $_
  Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object {
    $items += [pscustomobject]@{
      DriveLetter = [string]$_.DriveLetter
      Model = [string]$disk.FriendlyName
      Serial = [string]$disk.SerialNumber
      DiskNumber = [int]$disk.Number
    }
  }
}
$items | ConvertTo-Json -Compress
"#;
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", script])
            .output();
        let Ok(output) = output else {
            return HashMap::new();
        };
        let text = String::from_utf8_lossy(&output.stdout);
        if text.trim().is_empty() {
            return HashMap::new();
        }

        let json: serde_json::Value = match serde_json::from_str(&text) {
            Ok(value) => value,
            Err(_) => return HashMap::new(),
        };
        let values: Vec<serde_json::Value> = if let Some(array) = json.as_array() {
            array.clone()
        } else {
            vec![json]
        };

        let mut map = HashMap::new();
        for value in values {
            let letter = value
                .get("DriveLetter")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            if letter.is_empty() {
                continue;
            }
            map.insert(
                letter,
                PsMeta {
                    model: value
                        .get("Model")
                        .and_then(|v| v.as_str())
                        .map(str::to_string),
                    serial: value
                        .get("Serial")
                        .and_then(|v| v.as_str())
                        .map(str::to_string),
                    disk_number: value
                        .get("DiskNumber")
                        .and_then(|v| v.as_u64())
                        .map(|v| v as u32),
                },
            );
        }
        map
    }
    fn disk_device_id(drive: &Drive) -> Result<String, PlatformError> {
        let disk_number = drive
            .disk_number
            .ok_or_else(|| PlatformError::DriveNotFound(drive.drive.clone()))?;
        let script = format!(
            "Get-CimInstance Win32_DiskDrive | Where-Object {{ $_.Index -eq {disk_number} }} | Select-Object -ExpandProperty PNPDeviceID"
        );
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .output()
            .map_err(|err| PlatformError::Operation(err.to_string()))?;
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if text.is_empty() {
            Err(PlatformError::DriveNotFound(drive.drive.clone()))
        } else {
            Ok(text)
        }
    }

    pub fn windows_search_excludes_drive(letter: char) -> bool {
        let script = format!(
            r#"
$path = 'HKLM:\SOFTWARE\Microsoft\Windows Search\CrawlScopeManager\Windows\SystemIndex\WorkingSetRules'
if (-not (Test-Path -LiteralPath $path)) {{ 'false'; return }}
$letter = '{letter}'.ToUpperInvariant()
$pattern = "^file:///$letter`:(\\|/)(\[[^\]]+\](\\|/)?)?$"
$excluded = @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {{
    Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
}} | Where-Object {{
    $_.Include -eq 0 -and [string]$_.URL -match $pattern
}}).Count -gt 0
if ($excluded) {{ 'true' }} else {{ 'false' }}
"#
        );
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .output();
        output
            .map(|output| String::from_utf8_lossy(&output.stdout).contains("true"))
            .unwrap_or(false)
    }

    fn locate_devinst(device_id: &str) -> Result<u32, PlatformError> {
        let mut devinst = 0u32;
        let device_id_w = wide(device_id);
        let locate = unsafe {
            CM_Locate_DevNodeW(&mut devinst, device_id_w.as_ptr(), CM_LOCATE_DEVNODE_NORMAL)
        };
        if locate == CR_SUCCESS {
            Ok(devinst)
        } else {
            Err(map_configret(
                locate,
                format!("CM_Locate_DevNodeW({device_id})"),
            ))
        }
    }

    fn eject_devinst_for_disk(disk_devinst: u32) -> Option<u32> {
        let mut current = disk_devinst;
        while let Ok(Some(parent)) = parent_devinst(current) {
            current = parent;
            let Ok(device_id) = devinst_device_id(current) else {
                continue;
            };
            let id = device_id.to_ascii_uppercase();
            if id.starts_with("USB\\VID_") || id.starts_with("USBSTOR\\") {
                return Some(current);
            }
        }
        None
    }

    fn devinst_device_id(devinst: u32) -> Result<String, PlatformError> {
        let mut buffer = vec![0u16; 1024];
        let cr = unsafe { CM_Get_Device_IDW(devinst, buffer.as_mut_ptr(), buffer.len() as u32, 0) };
        if cr == CR_SUCCESS {
            Ok(from_wide_z(&buffer))
        } else {
            Err(map_configret(cr, "CM_Get_Device_IDW".to_string()))
        }
    }

    fn parent_devinst(devinst: u32) -> Result<Option<u32>, PlatformError> {
        let mut parent = 0u32;
        let cr = unsafe { CM_Get_Parent(&mut parent, devinst, 0) };
        match cr {
            CR_SUCCESS => Ok(Some(parent)),
            CR_NO_SUCH_DEVNODE | CR_INVALID_DEVNODE => Ok(None),
            other => Err(map_configret(other, "CM_Get_Parent".to_string())),
        }
    }

    fn map_configret(cr: u32, context: String) -> PlatformError {
        match cr {
            CR_ACCESS_DENIED => PlatformError::AccessDenied,
            CR_NO_SUCH_DEVNODE | CR_INVALID_DEVNODE => PlatformError::NotEjectable(context),
            other => PlatformError::Operation(format!("{context} failed: CONFIGRET 0x{other:08X}")),
        }
    }

    fn map_veto_type(value: PNP_VETO_TYPE) -> VetoType {
        match value as i32 {
            x if x == PNP_VetoLegacyDevice => VetoType::LegacyDevice,
            x if x == PNP_VetoPendingClose => VetoType::PendingClose,
            x if x == PNP_VetoWindowsApp => VetoType::WindowsApp,
            x if x == PNP_VetoWindowsService => VetoType::WindowsService,
            x if x == PNP_VetoOutstandingOpen => VetoType::OutstandingOpen,
            x if x == PNP_VetoDevice => VetoType::Device,
            x if x == PNP_VetoDriver => VetoType::Driver,
            x if x == PNP_VetoIllegalDeviceRequest => VetoType::IllegalDeviceRequest,
            x if x == PNP_VetoInsufficientPower => VetoType::InsufficientPower,
            x if x == PNP_VetoNonDisableable => VetoType::NonDisableable,
            x if x == PNP_VetoLegacyDriver => VetoType::LegacyDriver,
            x if x == PNP_VetoInsufficientRights => VetoType::InsufficientRights,
            x if x == PNP_VetoAlreadyRemoved => VetoType::AlreadyRemoved,
            _ => VetoType::TypeUnknown,
        }
    }

    fn remediation_keys(value: PNP_VETO_TYPE, event: Option<&EjectVetoEvent>) -> Vec<String> {
        if event
            .and_then(|event| event.process_name.as_ref())
            .is_some()
        {
            return vec!["step-close-risk-apps", "step-retry-safe-eject"]
                .into_iter()
                .map(str::to_string)
                .collect();
        }

        let keys = match value as i32 {
            x if x == PNP_VetoPendingClose || x == PNP_VetoOutstandingOpen => {
                vec!["step-close-risk-apps", "step-retry-safe-eject"]
            }
            x if x == PNP_VetoWindowsApp || x == PNP_VetoWindowsService => {
                vec!["step-close-blockers", "step-retry-safe-eject"]
            }
            _ => vec!["step-do-not-hard-unplug", "step-shutdown-if-still-fails"],
        };
        keys.into_iter().map(str::to_string).collect()
    }

    fn drive_still_present(letter: char) -> bool {
        let root = format!("{letter}:\\");
        std::path::Path::new(&root).exists()
    }

    fn drive_still_present_after_eject(letter: char) -> bool {
        for _ in 0..20 {
            if !drive_still_present(letter) {
                return false;
            }
            thread::sleep(Duration::from_millis(100));
        }
        true
    }

    fn wide(value: &str) -> Vec<u16> {
        value.encode_utf16().chain(std::iter::once(0)).collect()
    }

    fn from_wide_z(value: &[u16]) -> String {
        let len = value.iter().position(|c| *c == 0).unwrap_or(value.len());
        String::from_utf16_lossy(&value[..len])
    }

    fn non_empty_wide(value: &[u16]) -> Option<String> {
        let value = from_wide_z(value);
        if value.trim().is_empty() {
            None
        } else {
            Some(value)
        }
    }
}
