use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Drive {
    pub drive: String,
    pub label: Option<String>,
    pub model: String,
    pub serial: Option<String>,
    pub file_system: Option<String>,
    pub allocation_unit_kb: Option<u64>,
    pub size_gb: Option<u64>,
    pub free_gb: Option<u64>,
    pub disk_number: Option<u32>,
    pub is_samsung_t_series: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub enum ReadinessStatus {
    Ready,
    Caution,
    Blocked,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum BlockerKind {
    SearchIndexer,
    SamsungMagician,
    Explorer,
    DiskRetry,
    EjectVeto,
    FormatMismatch,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Blocker {
    pub kind: BlockerKind,
    pub process_name: Option<String>,
    pub pid: Option<u32>,
    pub message_key: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FormatPolicy {
    pub recommended_file_system: String,
    pub recommended_allocation_unit_kb: u64,
    pub matches: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Evidence {
    pub format_policy: FormatPolicy,
    pub disk_retry_count: u32,
    pub eject_veto_count: u32,
    pub global_eject_veto_count: u32,
    pub checked_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Recommendation {
    pub headline_key: String,
    pub primary_action_key: String,
    pub next_step_keys: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadinessReport {
    pub drive: Drive,
    pub status: ReadinessStatus,
    pub blockers: Vec<Blocker>,
    pub evidence: Evidence,
    pub recommendation: Recommendation,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "result", rename_all = "kebab-case")]
pub enum EjectOutcome {
    Ok {
        drive: String,
        still_present: bool,
        elapsed_ms: u64,
    },
    Vetoed {
        drive: String,
        veto_type: VetoType,
        veto_name: Option<String>,
        veto_process_name: Option<String>,
        veto_process_id: Option<u32>,
        veto_process_command_line: Option<String>,
        affected_device: Option<String>,
        still_present: bool,
        remediation_keys: Vec<String>,
        elapsed_ms: u64,
    },
    NotEjectable {
        drive: String,
        reason_key: String,
        elapsed_ms: u64,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VetoType {
    #[serde(rename = "PNP_VetoTypeUnknown")]
    TypeUnknown,
    #[serde(rename = "PNP_VetoLegacyDevice")]
    LegacyDevice,
    #[serde(rename = "PNP_VetoPendingClose")]
    PendingClose,
    #[serde(rename = "PNP_VetoWindowsApp")]
    WindowsApp,
    #[serde(rename = "PNP_VetoWindowsService")]
    WindowsService,
    #[serde(rename = "PNP_VetoOutstandingOpen")]
    OutstandingOpen,
    #[serde(rename = "PNP_VetoDevice")]
    Device,
    #[serde(rename = "PNP_VetoDriver")]
    Driver,
    #[serde(rename = "PNP_VetoIllegalDeviceRequest")]
    IllegalDeviceRequest,
    #[serde(rename = "PNP_VetoInsufficientPower")]
    InsufficientPower,
    #[serde(rename = "PNP_VetoNonDisableable")]
    NonDisableable,
    #[serde(rename = "PNP_VetoLegacyDriver")]
    LegacyDriver,
    #[serde(rename = "PNP_VetoInsufficientRights")]
    InsufficientRights,
    #[serde(rename = "PNP_VetoAlreadyRemoved")]
    AlreadyRemoved,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventCounters {
    pub critical_disk_retry: u32,
    pub historical_disk_retry: u32,
    pub eject_veto: u32,
    pub global_eject_veto: u32,
    pub window_days: u32,
    pub critical_minutes: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eject_veto_serializes_cfgmgr_veto_name() {
        let outcome = EjectOutcome::Vetoed {
            drive: "E:".to_string(),
            veto_type: VetoType::OutstandingOpen,
            veto_name: Some("explorer.exe".to_string()),
            veto_process_name: Some("explorer.exe".to_string()),
            veto_process_id: Some(1234),
            veto_process_command_line: Some(r#"C:\Windows\explorer.exe"#.to_string()),
            affected_device: Some(r#"STORAGE\Volume\{test}"#.to_string()),
            still_present: true,
            remediation_keys: vec!["step-close-risk-apps".to_string()],
            elapsed_ms: 12,
        };

        let json = serde_json::to_string(&outcome).unwrap();
        assert!(json.contains(r#""result":"vetoed""#));
        assert!(json.contains(r#""veto_type":"PNP_VetoOutstandingOpen""#));
        assert!(json.contains(r#""veto_name":"explorer.exe""#));
        assert!(json.contains(r#""veto_process_id":1234"#));
    }

    #[test]
    fn event_counters_separate_current_and_historical_disk_retries() {
        let counters = EventCounters {
            critical_disk_retry: 0,
            historical_disk_retry: 94,
            eject_veto: 0,
            global_eject_veto: 1,
            window_days: 7,
            critical_minutes: 30,
        };

        let json = serde_json::to_string(&counters).unwrap();
        assert!(json.contains(r#""critical_disk_retry":0"#));
        assert!(json.contains(r#""historical_disk_retry":94"#));
    }
}
