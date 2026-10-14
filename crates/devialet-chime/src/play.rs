//! The one I/O step: spawn `paplay` with the computed stream volume, wait,
//! and propagate its exit status. `paplay` (libpulse) is already a hard
//! dependency of plasma-pa on any Plasma system with audio, so it adds no
//! new dependency. stderr is inherited so paplay errors land in the same
//! journal stream as our own log line.

use std::process::{Command, ExitCode};

pub fn play(volume: u32, path: &str) -> ExitCode {
    match Command::new("paplay")
        .arg(format!("--volume={volume}"))
        .arg(path)
        .status()
    {
        Ok(status) if status.success() => ExitCode::SUCCESS,
        Ok(status) => {
            eprintln!("devialet-chime: paplay exited with {status}");
            ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("devialet-chime: failed to spawn paplay: {e}");
            ExitCode::FAILURE
        }
    }
}
