//! Reads the chime's two volumes from the daemon over D-Bus, bounded in time.
//!
//! Used when QML passes no `--target-db`/`--confirmed-db` (it runs only
//! `devialet-chime --tick k`, so Plasma's executable engine sees at most 16
//! distinct command strings for the life of the shell - every never-seen
//! name permanently grows every executable DataSource in plasmashell, see
//! TODO.md's "Scroll stutter" entry). The daemon already holds exactly what
//! QML used to pass:
//!
//! - `VolumeDb` - pending-masked, i.e. the latest `NotifyVolumeCommand`'s
//!   target (the OSD's own number);
//! - `VolumeRaw` - the amp's real last-broadcast byte, decoded with
//!   `devialet_protocol::volume_db_from_raw` (QML's `confirmedVolumeDb`);
//! - `AmpIp` - `""` when no amp is selected; `VolumeRaw` is then 0, not a
//!   volume.
//!
//! All three come from ONE `GetAll` on the interface, so target and
//! confirmed are the same snapshot (owner requirement).
//!
//! Never hangs (owner requirement): the whole read - bus connect, auth and
//! the call - runs on a helper thread and the caller waits at most
//! `timeout`. zbus's own `method_timeout` would not cover the connect/auth
//! handshake. On any failure the caller falls back to a default loudness
//! (see `resolve`) and logs why; it never fails silently.

use std::collections::HashMap;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use zbus::zvariant::OwnedValue;

pub const SERVICE: &str = "com.ekmanch.DevialetRemote";
pub const PATH: &str = "/com/ekmanch/DevialetRemote/Amp";
pub const INTERFACE: &str = "com.ekmanch.DevialetRemote.Amp1";

/// PROVISIONAL (2026-09-29): the plan's cap. Replaced by a value derived
/// from measured `read_ms` (about 10x the observed p99, never above 50 ms)
/// once the widget passes no dB arguments and real reads can be timed.
pub const DAEMON_READ_TIMEOUT: Duration = Duration::from_millis(50);

#[derive(Debug, Clone, PartialEq)]
pub struct Reading {
    pub target_db: f64,
    pub confirmed_db: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Unavailable {
    /// No reply within the timeout (bus or daemon stalled).
    Timeout,
    /// The daemon answered but has no amp selected (`AmpIp` empty).
    NoAmp,
    /// Connect or call failed (no session bus, name not owned, D-Bus
    /// error), or the reply lacked a property / had the wrong type.
    Failed(String),
}

impl std::fmt::Display for Unavailable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Unavailable::Timeout => write!(f, "timeout"),
            Unavailable::NoAmp => write!(f, "no amp selected"),
            Unavailable::Failed(e) => write!(f, "{e}"),
        }
    }
}

/// Reads the volumes, waiting at most `timeout`. Returns the result and how
/// long the caller waited (logged as `read_ms`).
pub fn read_volumes(timeout: Duration) -> (Result<Reading, Unavailable>, Duration) {
    let started = Instant::now();
    let (tx, rx) = mpsc::channel();
    // Detached on purpose: if it is still blocked when the timeout fires,
    // it dies with the process a moment later.
    std::thread::spawn(move || {
        let _ = tx.send(read_blocking());
    });
    let result = match rx.recv_timeout(timeout) {
        Ok(r) => r,
        Err(mpsc::RecvTimeoutError::Timeout) => Err(Unavailable::Timeout),
        Err(mpsc::RecvTimeoutError::Disconnected) => Err(Unavailable::Failed("reader thread died".to_string())),
    };
    (result, started.elapsed())
}

fn read_blocking() -> Result<Reading, Unavailable> {
    let fail = |e: zbus::Error| Unavailable::Failed(e.to_string());
    let conn = zbus::blocking::Connection::session().map_err(fail)?;
    let reply = conn
        .call_method(
            Some(SERVICE),
            PATH,
            Some("org.freedesktop.DBus.Properties"),
            "GetAll",
            &(INTERFACE,),
        )
        .map_err(fail)?;
    let props: HashMap<String, OwnedValue> = reply.body().deserialize().map_err(fail)?;
    extract(&props)
}

/// Pure: picks the three properties out of one `GetAll` reply.
pub fn extract(props: &HashMap<String, OwnedValue>) -> Result<Reading, Unavailable> {
    fn get<'a, T>(props: &'a HashMap<String, OwnedValue>, name: &str) -> Result<T, Unavailable>
    where
        T: TryFrom<&'a OwnedValue>,
    {
        let v = props
            .get(name)
            .ok_or_else(|| Unavailable::Failed(format!("reply has no {name}")))?;
        T::try_from(v).map_err(|_| Unavailable::Failed(format!("{name} has an unexpected type")))
    }
    let amp_ip: &str = props
        .get("AmpIp")
        .ok_or_else(|| Unavailable::Failed("reply has no AmpIp".to_string()))?
        .downcast_ref()
        .map_err(|_| Unavailable::Failed("AmpIp has an unexpected type".to_string()))?;
    if amp_ip.is_empty() {
        return Err(Unavailable::NoAmp);
    }
    let target_db: f64 = get(props, "VolumeDb")?;
    let raw: u8 = get(props, "VolumeRaw")?;
    Ok(Reading {
        target_db,
        confirmed_db: devialet_protocol::volume_db_from_raw(raw),
    })
}

/// What the chime computes its gain from, and where it came from (logged).
#[derive(Debug, Clone, PartialEq)]
pub struct Inputs {
    pub target_db: f64,
    pub confirmed_db: f64,
    pub source: String,
}

/// Pure: daemon values, or the default loudness when they're unavailable.
/// The default is a zero delta - gain 0 dB, the file at its own level,
/// which is what the chime already plays when the amp has caught up and
/// what the settings page's preview plays.
pub fn resolve(result: Result<Reading, Unavailable>) -> Inputs {
    match result {
        Ok(r) => Inputs {
            target_db: r.target_db,
            confirmed_db: r.confirmed_db,
            source: "daemon".to_string(),
        },
        Err(why) => Inputs {
            target_db: 0.0,
            confirmed_db: 0.0,
            source: format!("default({why})"),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::Value;

    fn props(amp_ip: &str, volume_db: f64, volume_raw: u8) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        m.insert("AmpIp".to_string(), OwnedValue::try_from(Value::from(amp_ip)).unwrap());
        m.insert("VolumeDb".to_string(), OwnedValue::from(volume_db));
        m.insert("VolumeRaw".to_string(), OwnedValue::from(volume_raw));
        // GetAll also returns everything else; extract() must ignore it.
        m.insert("Muted".to_string(), OwnedValue::from(false));
        m
    }

    #[test]
    fn extract_reads_target_and_decodes_confirmed() {
        let r = extract(&props("192.168.0.22", -30.0, 125)).unwrap();
        assert_eq!(r.target_db, -30.0);
        assert_eq!(r.confirmed_db, -35.0); // (125 - 195) / 2
    }

    #[test]
    fn extract_no_amp_is_unavailable() {
        assert_eq!(extract(&props("", -97.5, 0)), Err(Unavailable::NoAmp));
    }

    #[test]
    fn extract_missing_or_mistyped_property_fails() {
        let mut m = props("192.168.0.22", -30.0, 125);
        m.remove("VolumeRaw");
        assert!(matches!(extract(&m), Err(Unavailable::Failed(e)) if e.contains("VolumeRaw")));
        let mut m = props("192.168.0.22", -30.0, 125);
        m.insert("VolumeDb".to_string(), OwnedValue::from(7u8));
        assert!(matches!(extract(&m), Err(Unavailable::Failed(e)) if e.contains("VolumeDb")));
    }

    #[test]
    fn resolve_daemon_values() {
        let i = resolve(Ok(Reading { target_db: -30.0, confirmed_db: -35.0 }));
        assert_eq!((i.target_db, i.confirmed_db, i.source.as_str()), (-30.0, -35.0, "daemon"));
    }

    #[test]
    fn resolve_unavailable_falls_back_to_zero_delta() {
        for (why, text) in [
            (Unavailable::Timeout, "default(timeout)"),
            (Unavailable::NoAmp, "default(no amp selected)"),
            (Unavailable::Failed("boom".to_string()), "default(boom)"),
        ] {
            let i = resolve(Err(why));
            assert_eq!((i.target_db, i.confirmed_db), (0.0, 0.0));
            assert_eq!(i.source, text);
        }
    }
}
