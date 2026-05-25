use crate::model::{
    Blocker, BlockerKind, Drive, Evidence, FormatPolicy, ReadinessReport, ReadinessStatus,
    Recommendation,
};

pub fn evaluate_readiness(
    drive: Drive,
    mut blockers: Vec<Blocker>,
    disk_retry_count: u32,
    eject_veto_count: u32,
    global_eject_veto_count: u32,
) -> ReadinessReport {
    let format_policy = format_policy_for_drive(&drive);
    if !format_policy.matches {
        blockers.push(Blocker {
            kind: BlockerKind::FormatMismatch,
            process_name: None,
            pid: None,
            message_key: "blocker-format-mismatch".to_string(),
        });
    }

    let has_critical_blocker = disk_retry_count > 0 || eject_veto_count > 0;
    let has_caution = !blockers.is_empty() || global_eject_veto_count > 0;
    let status = if has_critical_blocker {
        ReadinessStatus::Blocked
    } else if has_caution {
        ReadinessStatus::Caution
    } else {
        ReadinessStatus::Ready
    };

    let recommendation = recommendation_for(status, &blockers, disk_retry_count, eject_veto_count);

    ReadinessReport {
        drive,
        status,
        blockers,
        evidence: Evidence {
            format_policy,
            disk_retry_count,
            eject_veto_count,
            global_eject_veto_count,
            checked_at: None,
        },
        recommendation,
    }
}

pub fn format_policy_for_drive(drive: &Drive) -> FormatPolicy {
    let recommended_allocation_unit_kb = if drive.model.to_ascii_lowercase().contains("t7 shield")
        && drive.size_gb.unwrap_or_default() > 3000
    {
        256
    } else {
        128
    };

    let matches = drive
        .file_system
        .as_deref()
        .map(|fs| fs.eq_ignore_ascii_case("exFAT"))
        .unwrap_or(false)
        && drive.allocation_unit_kb == Some(recommended_allocation_unit_kb);

    FormatPolicy {
        recommended_file_system: "exFAT".to_string(),
        recommended_allocation_unit_kb,
        matches,
    }
}

fn recommendation_for(
    status: ReadinessStatus,
    blockers: &[Blocker],
    disk_retry_count: u32,
    eject_veto_count: u32,
) -> Recommendation {
    let has_search = blockers
        .iter()
        .any(|b| b.kind == BlockerKind::SearchIndexer);
    let has_magician = blockers
        .iter()
        .any(|b| b.kind == BlockerKind::SamsungMagician);

    let headline_key = match status {
        ReadinessStatus::Ready => "headline-ready",
        ReadinessStatus::Caution if has_search => "headline-caution-search-indexer",
        ReadinessStatus::Caution if has_magician => "headline-caution-samsung-magician",
        ReadinessStatus::Caution => "headline-caution",
        ReadinessStatus::Blocked if eject_veto_count > 0 => "headline-blocked-eject-veto",
        ReadinessStatus::Blocked if disk_retry_count > 0 => "headline-blocked-disk-retry",
        ReadinessStatus::Blocked => "headline-blocked",
        ReadinessStatus::Unknown => "headline-unknown",
    };

    let primary_action_key = match status {
        ReadinessStatus::Ready => "action-safe-eject",
        ReadinessStatus::Caution => "action-close-apps-then-eject",
        ReadinessStatus::Blocked => "action-shutdown-before-unplug",
        ReadinessStatus::Unknown => "action-refresh-or-diagnose",
    };

    let next_step_keys = match status {
        ReadinessStatus::Ready => vec!["step-click-safe-eject", "step-unplug-after-success"],
        ReadinessStatus::Caution if has_search => vec![
            "step-stop-search-if-needed",
            "step-close-samsung-magician",
            "step-retry-safe-eject",
        ],
        ReadinessStatus::Caution => vec![
            "step-close-risk-apps",
            "step-retry-safe-eject",
            "step-open-diagnostics-if-fails",
        ],
        ReadinessStatus::Blocked => vec![
            "step-do-not-hard-unplug",
            "step-close-blockers",
            "step-shutdown-if-still-fails",
        ],
        ReadinessStatus::Unknown => vec![
            "step-refresh-status",
            "step-open-diagnostics-if-fails",
            "step-shutdown-if-unsure",
        ],
    }
    .into_iter()
    .map(str::to_string)
    .collect();

    Recommendation {
        headline_key: headline_key.to_string(),
        primary_action_key: primary_action_key.to_string(),
        next_step_keys,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn drive(serial: Option<&str>, au: Option<u64>, size_gb: Option<u64>) -> Drive {
        Drive {
            drive: "E:".to_string(),
            label: Some("TEST_T7".to_string()),
            model: "Samsung PSSD T7 Shield".to_string(),
            serial: serial.map(str::to_string),
            file_system: Some("exFAT".to_string()),
            allocation_unit_kb: au,
            size_gb,
            free_gb: None,
            disk_number: Some(4),
            is_samsung_t_series: true,
        }
    }

    #[test]
    fn t7_shield_4tb_keeps_256kb_policy() {
        let policy =
            format_policy_for_drive(&drive(Some("TEST_T7_SHIELD_SERIAL"), Some(256), Some(3726)));
        assert_eq!(policy.recommended_allocation_unit_kb, 256);
        assert!(policy.matches);
    }

    #[test]
    fn caution_when_search_indexer_blocks() {
        let report = evaluate_readiness(
            drive(Some("TEST_T7_SHIELD_SERIAL"), Some(256), Some(3726)),
            vec![Blocker {
                kind: BlockerKind::SearchIndexer,
                process_name: Some("SearchIndexer".to_string()),
                pid: Some(14076),
                message_key: "blocker-search-indexer".to_string(),
            }],
            0,
            0,
            0,
        );
        assert_eq!(report.status, ReadinessStatus::Caution);
        assert_eq!(
            report.recommendation.primary_action_key,
            "action-close-apps-then-eject"
        );
    }

    #[test]
    fn blocked_when_disk_retry_exists() {
        let report = evaluate_readiness(
            drive(Some("TEST_T7_SHIELD_SERIAL"), Some(256), Some(3726)),
            vec![],
            1,
            0,
            0,
        );
        assert_eq!(report.status, ReadinessStatus::Blocked);
        assert_eq!(
            report.recommendation.primary_action_key,
            "action-shutdown-before-unplug"
        );
    }
}
