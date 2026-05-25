use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use serde::Serialize;
use stc_core::{
    EjectOutcome, PlatformDriveProvider, PlatformError, ReadinessReport, SystemDriveProvider,
    evaluate_readiness,
};
use std::io::{self, Write};
use std::process::ExitCode;

#[derive(Debug, Parser)]
#[command(name = "stc")]
#[command(about = "Samsung T-Series Console CLI")]
struct Cli {
    #[arg(long, default_value = "json")]
    output: OutputMode,
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Clone, clap::ValueEnum)]
enum OutputMode {
    Json,
    Text,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// List detected Samsung T-series removable drives.
    List,
    /// Show daily safe-eject readiness for all drives or one drive letter.
    Readiness {
        #[arg(long)]
        drive: Option<String>,
    },
    /// Print a read-only diagnostic summary.
    Doctor {
        #[arg(long)]
        verbose: bool,
        #[arg(long, default_value = "7")]
        window_days: u32,
    },
    /// Safely eject a Samsung T-series drive.
    Eject {
        drive: String,
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Debug, Serialize)]
struct Envelope<T: Serialize> {
    command: &'static str,
    payload: T,
}

#[derive(Debug, Serialize)]
struct DoctorReport {
    #[serde(flatten)]
    readiness: ReadinessReport,
    #[serde(skip_serializing_if = "Option::is_none")]
    event_counters: Option<stc_core::EventCounters>,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(err) => {
            eprintln!("{err:#}");
            ExitCode::from(20)
        }
    }
}

fn run() -> Result<u8> {
    let cli = Cli::parse();
    let provider = SystemDriveProvider;
    match cli.command {
        Command::List => {
            let drives = provider.list_drives().context("failed to list drives")?;
            print_output(
                &cli.output,
                &Envelope {
                    command: "list",
                    payload: drives,
                },
            )?;
        }
        Command::Readiness { drive } => {
            let drives = provider.list_drives().context("failed to list drives")?;
            let reports = drives
                .into_iter()
                .filter(|d| {
                    drive
                        .as_ref()
                        .map(|requested| d.drive.eq_ignore_ascii_case(requested))
                        .unwrap_or(true)
                })
                .map(|d| {
                    let blockers = provider.current_blockers(&d).unwrap_or_default();
                    evaluate_readiness(d, blockers, 0, 0, 0)
                })
                .collect::<Vec<_>>();
            print_output(
                &cli.output,
                &Envelope {
                    command: "readiness",
                    payload: reports,
                },
            )?;
        }
        Command::Doctor {
            verbose,
            window_days,
        } => {
            let drives = provider.list_drives().context("failed to list drives")?;
            let reports = drives
                .into_iter()
                .map(|d| {
                    let blockers = provider.current_blockers(&d).unwrap_or_default();
                    let counters = if verbose {
                        Some(provider.event_counters(&d, window_days).unwrap_or(
                            stc_core::EventCounters {
                                critical_disk_retry: 0,
                                historical_disk_retry: 0,
                                eject_veto: 0,
                                global_eject_veto: 0,
                                window_days,
                                critical_minutes: 30,
                            },
                        ))
                    } else {
                        None
                    };
                    let report = evaluate_readiness(
                        d,
                        blockers,
                        counters
                            .as_ref()
                            .map(|c| c.critical_disk_retry)
                            .unwrap_or(0),
                        counters.as_ref().map(|c| c.eject_veto).unwrap_or(0),
                        counters.as_ref().map(|c| c.global_eject_veto).unwrap_or(0),
                    );
                    DoctorReport {
                        readiness: report,
                        event_counters: counters,
                    }
                })
                .collect::<Vec<_>>();
            print_output(
                &cli.output,
                &Envelope {
                    command: "doctor",
                    payload: reports,
                },
            )?;
        }
        Command::Eject { drive, yes } => {
            let drives = provider.list_drives().context("failed to list drives")?;
            let requested = normalize_drive(&drive)?;
            let Some(target) = drives
                .iter()
                .find(|d| normalize_drive(&d.drive).ok().as_deref() == Some(requested.as_str()))
            else {
                let outcome = EjectOutcome::NotEjectable {
                    drive: requested,
                    reason_key: "drive-not-found".to_string(),
                    elapsed_ms: 0,
                };
                print_output(
                    &cli.output,
                    &Envelope {
                        command: "eject",
                        payload: outcome,
                    },
                )?;
                return Ok(11);
            };

            if !yes && !confirm_eject(target)? {
                eprintln!("eject declined by user");
                return Ok(30);
            }

            match provider.eject(target) {
                Ok(outcome) => {
                    let code = match outcome {
                        EjectOutcome::Ok { .. } => 0,
                        EjectOutcome::Vetoed { .. } => 10,
                        EjectOutcome::NotEjectable { .. } => 12,
                    };
                    print_output(
                        &cli.output,
                        &Envelope {
                            command: "eject",
                            payload: outcome,
                        },
                    )?;
                    return Ok(code);
                }
                Err(err) => {
                    let code = platform_error_code(&err);
                    eprintln!("{err}");
                    return Ok(code);
                }
            }
        }
    }
    Ok(0)
}

fn print_output<T: serde::Serialize + std::fmt::Debug>(mode: &OutputMode, value: &T) -> Result<()> {
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string_pretty(value)?);
        }
        OutputMode::Text => {
            println!("{value:#?}");
        }
    }
    Ok(())
}

fn normalize_drive(value: &str) -> Result<String> {
    let letter = value
        .chars()
        .find(|c| c.is_ascii_alphabetic())
        .context("drive must contain a letter")?
        .to_ascii_uppercase();
    Ok(format!("{letter}:"))
}

fn confirm_eject(drive: &stc_core::Drive) -> Result<bool> {
    eprintln!(
        "Eject {} {} {}? [y/N]",
        drive.drive,
        drive.model,
        drive.serial.as_deref().unwrap_or("")
    );
    io::stderr().flush().ok();
    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    Ok(matches!(input.trim(), "y" | "Y" | "yes" | "YES"))
}

fn platform_error_code(err: &PlatformError) -> u8 {
    match err {
        PlatformError::DriveNotFound(_) => 11,
        PlatformError::NotEjectable(_) => 12,
        PlatformError::AccessDenied => 13,
        PlatformError::Unsupported(_) | PlatformError::Operation(_) => 20,
    }
}
