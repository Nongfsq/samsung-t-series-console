pub mod model;
pub mod platform;
pub mod readiness;

pub use model::{
    Blocker, BlockerKind, Drive, EjectOutcome, EventCounters, Evidence, FormatPolicy,
    ReadinessReport, ReadinessStatus, Recommendation, VetoType,
};
pub use platform::{PlatformDriveProvider, PlatformError, SystemDriveProvider};
pub use readiness::evaluate_readiness;
