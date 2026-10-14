//! On-disk persistence for the explicitly selected amp IP. Plain text, no
//! serde: the file is one line holding either an IP or an empty string
//! (an explicit "None", which must stay distinct from "never chosen" -
//! see `AmpState::set_persisted_selection` in interface.rs).
//!
//! Location: `$XDG_CONFIG_HOME/devialet-remote-daemon/selected-amp-ip`,
//! falling back to `$HOME/.config/...` when `XDG_CONFIG_HOME` is unset or
//! empty (the XDG Base Directory spec's rule). Two env vars do not justify
//! a `dirs` crate dependency.
//!
//! Pure path/file logic with no D-Bus awareness; `AmpState::select_amp`
//! and `main()`'s startup decide when to call it.

use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

const CONFIG_SUBDIR: &str = "devialet-remote-daemon";
const CONFIG_FILE: &str = "selected-amp-ip";

/// Pure resolution logic, split from `config_dir()` so tests need not
/// mutate process env vars (racy across parallel test threads).
fn resolve_config_dir(xdg_config_home: Option<String>, home: Option<String>) -> Option<PathBuf> {
    if let Some(xdg) = xdg_config_home {
        if !xdg.is_empty() {
            return Some(PathBuf::from(xdg).join(CONFIG_SUBDIR));
        }
    }
    let home = home?;
    if home.is_empty() {
        return None;
    }
    Some(PathBuf::from(home).join(".config").join(CONFIG_SUBDIR))
}

fn config_dir() -> Option<PathBuf> {
    resolve_config_dir(env::var("XDG_CONFIG_HOME").ok(), env::var("HOME").ok())
}

fn config_path() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join(CONFIG_FILE))
}

/// Reads a persisted selection from an explicit path. `None` means
/// nothing persisted (file absent, or unreadable: fails open rather than
/// making a read error fatal at startup). `Some("")` is a real result, an
/// explicit "None".
fn load_from_path(path: &Path) -> Option<String> {
    match fs::read_to_string(path) {
        Ok(contents) => Some(contents.trim().to_string()),
        Err(e) if e.kind() == ErrorKind::NotFound => None,
        Err(e) => {
            eprintln!("config: failed to read {path:?}, ignoring persisted selection: {e}");
            None
        }
    }
}

/// Writes a selection to an explicit path, creating the parent directory
/// if needed. Best-effort: a write failure is logged and ignored, since
/// `SelectAmp` must succeed even if persisting it does not.
fn save_to_path(path: &Path, ip: &str) {
    let Some(dir) = path.parent() else { return };
    if let Err(e) = fs::create_dir_all(dir) {
        eprintln!("config: failed to create {dir:?}, selection not persisted: {e}");
        return;
    }
    if let Err(e) = fs::write(path, ip) {
        eprintln!("config: failed to write {path:?}, selection not persisted: {e}");
    }
}

/// Loads the persisted selected-amp IP, or `None` if nothing has ever been
/// persisted (first run, or `$HOME`/`$XDG_CONFIG_HOME` unresolvable).
/// Called once at daemon startup, before the D-Bus object server exists.
pub fn load_selected_ip() -> Option<String> {
    let path = config_path()?;
    load_from_path(&path)
}

/// Persists the selected-amp IP (or `""` for an explicit "None") so it
/// survives a daemon restart. Called from `AmpState::select_amp` on every
/// `SelectAmp` D-Bus call, including `SelectAmp("")`.
pub fn save_selected_ip(ip: &str) {
    let Some(path) = config_path() else {
        eprintln!("config: no usable XDG_CONFIG_HOME/HOME, cannot persist selected amp");
        return;
    };
    save_to_path(&path, ip);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xdg_config_home_takes_precedence_over_home() {
        let dir = resolve_config_dir(Some("/custom/xdg".to_string()), Some("/home/someone".to_string()));
        assert_eq!(dir, Some(PathBuf::from("/custom/xdg/devialet-remote-daemon")));
    }

    #[test]
    fn empty_xdg_config_home_falls_back_to_home_dot_config() {
        // The XDG spec falls back on "not set OR empty": an empty-but-set
        // var is not an override.
        let dir = resolve_config_dir(Some(String::new()), Some("/home/someone".to_string()));
        assert_eq!(dir, Some(PathBuf::from("/home/someone/.config/devialet-remote-daemon")));
    }

    #[test]
    fn unset_xdg_config_home_falls_back_to_home_dot_config() {
        let dir = resolve_config_dir(None, Some("/home/someone".to_string()));
        assert_eq!(dir, Some(PathBuf::from("/home/someone/.config/devialet-remote-daemon")));
    }

    #[test]
    fn no_xdg_and_no_home_resolves_to_nothing() {
        assert_eq!(resolve_config_dir(None, None), None);
        assert_eq!(resolve_config_dir(Some(String::new()), None), None);
        assert_eq!(resolve_config_dir(Some(String::new()), Some(String::new())), None);
    }

    fn test_dir(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("devialet-daemon-config-test-{}-{}-{name}", std::process::id(), line!()))
    }

    #[test]
    fn nonexistent_file_loads_as_none_never_persisted() {
        let dir = test_dir("nonexistent");
        let path = dir.join(CONFIG_FILE);
        assert_eq!(load_from_path(&path), None, "a file that was never written must load as None, not Some(\"\")");
    }

    #[test]
    fn round_trips_a_real_ip() {
        let dir = test_dir("roundtrip-ip");
        let path = dir.join(CONFIG_FILE);
        save_to_path(&path, "192.168.1.50");
        assert_eq!(load_from_path(&path), Some("192.168.1.50".to_string()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn round_trips_an_explicit_empty_selection() {
        // The critical case: a persisted "" must load back as Some(""),
        // distinct from the nonexistent-file None, so the caller can set
        // has_explicit_selection for a persisted "None".
        let dir = test_dir("roundtrip-empty");
        let path = dir.join(CONFIG_FILE);
        save_to_path(&path, "");
        assert_eq!(load_from_path(&path), Some(String::new()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_later_save_overwrites_an_earlier_one() {
        let dir = test_dir("overwrite");
        let path = dir.join(CONFIG_FILE);
        save_to_path(&path, "192.168.1.50");
        save_to_path(&path, "192.168.1.51");
        assert_eq!(load_from_path(&path), Some("192.168.1.51".to_string()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn saved_content_is_trimmed_on_load() {
        let dir = test_dir("trim");
        let path = dir.join(CONFIG_FILE);
        fs::create_dir_all(&dir).unwrap();
        fs::write(&path, "192.168.1.50\n").unwrap();
        assert_eq!(load_from_path(&path), Some("192.168.1.50".to_string()));
        let _ = fs::remove_dir_all(&dir);
    }
}
