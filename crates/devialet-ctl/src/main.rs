//! Single-shot command CLI, invoked from QML via
//! `Plasma5Support.DataSource`'s executable engine. Builds one (or, for
//! `source`, two) logical UDP commands, sends each twice (docs/protocol.md)
//! and exits. No daemon, no D-Bus (docs/DESIGN.md §1).
//!
//! Usage:
//!   devialet-ctl --ip <amp-ip> power <on|off>
//!   devialet-ctl --ip <amp-ip> mute <on|off>
//!   devialet-ctl --ip <amp-ip> volume <db, e.g. -20.0> --hard-limit-db <db|none>
//!   devialet-ctl --ip <amp-ip> source <status-broadcast index, 0-29> --hard-limit-db <db|none> [--startup-volume-db <db>]
//!
//! `--ip` is required: each invocation is a fresh process with no notion of
//! a selected amp, so the caller supplies the target every time.
//!
//! `--hard-limit-db <db|none>` is **required** for `volume` and `source`;
//! a missing flag is a usage error, never a silent "unbounded". It feeds
//! `volume_packet`'s clamp for every volume-set command sent (`volume`,
//! and `source`'s post-switch volume). `none` (any case) is an explicit
//! choice of unbounded. Named flags rather than positional values so the
//! two optional values cannot be confused.
//!
//! The guarantee holds only for callers that pass the configured limit:
//! QML passes `volumeSettings.hardLimitDb` on every call
//! (FlyoutContent.qml, CompactRepresentation.qml). The CLI cannot derive
//! the widget's limit itself, so a manual invocation must pass the flag.
//!
//! `--startup-volume-db <db>` is **optional** and read only by `source`:
//! the post-switch volume, default `SOURCE_SWITCH_VOLUME_DB` (-40dB). It
//! is optional because omitting it falls back to a safe default, whereas
//! an omitted hard limit would be a safety gap. It is still clamped by
//! `--hard-limit-db`. Both flags are parsed globally, in either order.
//! Power-on has no equivalent: the CLI cannot wait for the amp to boot, so
//! the widget sends a separate `volume` once the daemon confirms the boot
//! (FlyoutContent.qml).
//!
//! Measured on the real amp: source×2 then volume×2 back-to-back, with no
//! settling time, was honored 6/6; the first broadcast ~200 ms later
//! already carried both the new index and the forced volume. No delay is
//! needed on this path.

use devialet_protocol as proto;
use std::net::{ToSocketAddrs, UdpSocket};
use std::process::ExitCode;

#[derive(Debug)]
struct Args {
    ip: String,
    command: String,
    value: String,
    /// `None` = flag not given (an error for `volume`/`source`, checked
    /// at the point of use). `Some(None)` = literal `none`, explicitly
    /// unbounded. `Some(Some(db))` = a real limit.
    hard_limit_db: Option<Option<f64>>,
    /// `None` = flag not given; `source` falls back to
    /// `proto::SOURCE_SWITCH_VOLUME_DB`.
    startup_volume_db: Option<f64>,
}

fn parse_args() -> Result<Args, String> {
    parse_args_from(std::env::args().skip(1).collect())
}

/// Pure parser over the arguments after argv[0], unit-testable without a
/// process.
fn parse_args_from(raw: Vec<String>) -> Result<Args, String> {
    if raw.len() < 4 || raw[0] != "--ip" {
        return Err(usage());
    }
    let ip = raw[1].clone();
    let command = raw[2].clone();
    let value = raw[3].clone();

    let mut hard_limit_db = None;
    let mut startup_volume_db = None;
    let mut i = 4;
    while i < raw.len() {
        match raw[i].as_str() {
            "--hard-limit-db" => {
                let v = raw
                    .get(i + 1)
                    .ok_or_else(|| format!("--hard-limit-db requires a value\n\n{}", usage()))?;
                hard_limit_db = Some(if v.eq_ignore_ascii_case("none") {
                    None
                } else {
                    Some(
                        v.parse::<f64>()
                            .map_err(|_| format!("expected a number or \"none\" for --hard-limit-db, got {:?}", v))?,
                    )
                });
                i += 2;
            }
            "--startup-volume-db" => {
                let v = raw
                    .get(i + 1)
                    .ok_or_else(|| format!("--startup-volume-db requires a value\n\n{}", usage()))?;
                startup_volume_db = Some(
                    v.parse::<f64>()
                        .map_err(|_| format!("expected a number for --startup-volume-db, got {:?}", v))?,
                );
                i += 2;
            }
            other => return Err(format!("unknown argument {other:?}\n\n{}", usage())),
        }
    }

    Ok(Args {
        ip,
        command,
        value,
        hard_limit_db,
        startup_volume_db,
    })
}

/// The volume `source` sends right after the switch: the caller's
/// `--startup-volume-db` when given, else the default
/// (docs/known-gotchas.md #5). `volume_packet` applies the hard-limit clamp.
fn post_switch_volume_db(args: &Args) -> f64 {
    args.startup_volume_db.unwrap_or(proto::SOURCE_SWITCH_VOLUME_DB)
}

fn usage() -> String {
    "usage: devialet-ctl --ip <amp-ip> <power|mute|volume|source> <value> [--hard-limit-db <db|none>] [--startup-volume-db <db>]\n\
     \n\
     \x20 power  on|off\n\
     \x20 mute   on|off\n\
     \x20 volume <db, e.g. -20.0>  --hard-limit-db <db|none>  (required; \"none\" = explicitly unbounded)\n\
     \x20 source <status-broadcast index, 0-29>  --hard-limit-db <db|none>  (required; applies to the forced post-switch volume)\n\
     \x20        [--startup-volume-db <db>]  (optional; post-switch volume instead of the default -40, still clamped by --hard-limit-db)"
        .to_string()
}

/// A missing `--hard-limit-db` is a usage error for `volume`/`source`;
/// only an explicit `none` means unbounded.
fn require_hard_limit(args: &Args) -> Result<Option<f64>, String> {
    args.hard_limit_db
        .ok_or_else(|| format!("--hard-limit-db is required (pass a number, or \"none\" to explicitly send unbounded)\n\n{}", usage()))
}

fn parse_on_off(value: &str) -> Result<bool, String> {
    match value {
        "on" => Ok(true),
        "off" => Ok(false),
        other => Err(format!("expected \"on\" or \"off\", got {other:?}")),
    }
}

/// Sends one logical command twice (docs/protocol.md); the two copies
/// carry different counter values. `counters` is `(packet, command)` and
/// advances once per send, so several logical commands in one invocation
/// (`source` + the follow-up volume) keep counting forward without reset.
fn send_twice(
    socket: &UdpSocket,
    build: impl Fn(u16, u16) -> [u8; proto::PACKET_LEN],
    counters: &mut (u16, u16),
) -> std::io::Result<()> {
    for _ in 0..2 {
        let packet = build(counters.0, counters.1);
        socket.send(&packet)?;
        counters.0 = proto::next_counter(counters.0);
        counters.1 = proto::next_counter(counters.1);
    }
    Ok(())
}

fn run() -> Result<(), String> {
    let args = parse_args()?;

    let addr = (args.ip.as_str(), proto::COMMAND_PORT)
        .to_socket_addrs()
        .map_err(|e| format!("invalid --ip {:?}: {e}", args.ip))?
        .next()
        .ok_or_else(|| format!("could not resolve --ip {:?}", args.ip))?;

    let socket = UdpSocket::bind("0.0.0.0:0").map_err(|e| format!("failed to open socket: {e}"))?;
    socket
        .connect(addr)
        .map_err(|e| format!("failed to target {addr}: {e}"))?;

    // Counters live for this invocation only and start at (0, 0). Whether
    // the amp needs them contiguous across invocations is "inferred, not
    // confirmed" in docs/protocol.md; if it does, persist them here.
    let mut counters: (u16, u16) = (0, 0);

    match args.command.as_str() {
        "power" => {
            let on = parse_on_off(&args.value)?;
            send_twice(&socket, |p, c| proto::power_packet(on, p, c), &mut counters)
                .map_err(|e| format!("send failed: {e}"))?;
        }
        "mute" => {
            let muted = parse_on_off(&args.value)?;
            send_twice(&socket, |p, c| proto::mute_packet(muted, p, c), &mut counters)
                .map_err(|e| format!("send failed: {e}"))?;
        }
        "volume" => {
            let db: f64 = args
                .value
                .parse()
                .map_err(|_| format!("expected a number for volume, got {:?}", args.value))?;
            let hard_limit_db = require_hard_limit(&args)?;
            send_twice(
                &socket,
                |p, c| proto::volume_packet(db, hard_limit_db, p, c),
                &mut counters,
            )
            .map_err(|e| format!("send failed: {e}"))?;
        }
        "source" => {
            let index: u8 = args
                .value
                .parse()
                .map_err(|_| format!("expected an integer 0-29 for source, got {:?}", args.value))?;
            let hard_limit_db = require_hard_limit(&args)?;
            send_twice(&socket, |p, c| proto::source_packet(index, p, c), &mut counters)
                .map_err(|e| format!("send failed: {e}"))?;
            // Forced follow-up volume after every source switch
            // (docs/known-gotchas.md #5), continuing the same counter
            // sequence. `--startup-volume-db` (the widget's configured
            // startup volume) or the -40dB default; `volume_packet` clamps
            // it to the hard limit like any other volume command.
            let post_switch_db = post_switch_volume_db(&args);
            send_twice(
                &socket,
                |p, c| proto::volume_packet(post_switch_db, hard_limit_db, p, c),
                &mut counters,
            )
            .map_err(|e| format!("send failed: {e}"))?;
        }
        other => return Err(format!("unknown command {other:?}\n\n{}", usage())),
    }

    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(msg) => {
            eprintln!("{msg}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Result<Args, String> {
        parse_args_from(list.iter().map(|s| s.to_string()).collect())
    }

    #[test]
    fn startup_volume_omitted_falls_back_to_default_without_error() {
        let a = args(&["--ip", "1.2.3.4", "source", "3", "--hard-limit-db", "-10"]).unwrap();
        assert_eq!(a.startup_volume_db, None);
        assert_eq!(post_switch_volume_db(&a), proto::SOURCE_SWITCH_VOLUME_DB);
        assert_eq!(a.hard_limit_db, Some(Some(-10.0)));
    }

    #[test]
    fn startup_volume_given_is_used() {
        let a = args(&["--ip", "1.2.3.4", "source", "3", "--hard-limit-db", "-10", "--startup-volume-db", "-33"]).unwrap();
        assert_eq!(a.startup_volume_db, Some(-33.0));
        assert_eq!(post_switch_volume_db(&a), -33.0);
    }

    #[test]
    fn both_flags_accepted_in_either_order() {
        let a = args(&["--ip", "1.2.3.4", "source", "0", "--startup-volume-db", "-30.5", "--hard-limit-db", "none"]).unwrap();
        assert_eq!(a.startup_volume_db, Some(-30.5));
        assert_eq!(a.hard_limit_db, Some(None));
        let b = args(&["--ip", "1.2.3.4", "source", "0", "--hard-limit-db", "none", "--startup-volume-db", "-30.5"]).unwrap();
        assert_eq!(b.startup_volume_db, Some(-30.5));
        assert_eq!(b.hard_limit_db, Some(None));
    }

    #[test]
    fn startup_volume_missing_value_is_an_error() {
        let e = args(&["--ip", "1.2.3.4", "source", "0", "--hard-limit-db", "-10", "--startup-volume-db"]).unwrap_err();
        assert!(e.contains("--startup-volume-db requires a value"), "{e}");
    }

    #[test]
    fn startup_volume_non_numeric_is_an_error() {
        let e = args(&["--ip", "1.2.3.4", "source", "0", "--hard-limit-db", "-10", "--startup-volume-db", "loud"]).unwrap_err();
        assert!(e.contains("expected a number for --startup-volume-db"), "{e}");
        // No `none` literal for this flag, unlike --hard-limit-db.
        let e = args(&["--ip", "1.2.3.4", "source", "0", "--hard-limit-db", "-10", "--startup-volume-db", "none"]).unwrap_err();
        assert!(e.contains("expected a number for --startup-volume-db"), "{e}");
    }

    #[test]
    fn power_on_is_unaffected_by_the_flag() {
        let a = args(&["--ip", "1.2.3.4", "power", "on"]).unwrap();
        assert_eq!(a.command, "power");
        assert_eq!(a.startup_volume_db, None);
        assert_eq!(a.hard_limit_db, None);
        // Parsed globally, ignored by power - not an error either.
        let b = args(&["--ip", "1.2.3.4", "power", "on", "--startup-volume-db", "-20"]).unwrap();
        assert_eq!(b.startup_volume_db, Some(-20.0));
    }

    #[test]
    fn hard_limit_still_required_for_source_with_startup_volume() {
        let a = args(&["--ip", "1.2.3.4", "source", "0", "--startup-volume-db", "-20"]).unwrap();
        assert!(require_hard_limit(&a).unwrap_err().contains("--hard-limit-db is required"));
    }

    /// Documents the clamp on exactly the composition `source` uses:
    /// a startup volume above the hard limit produces the same packet as
    /// the limit itself.
    #[test]
    fn startup_volume_above_hard_limit_is_clamped_in_the_packet() {
        let a = args(&["--ip", "1.2.3.4", "source", "0", "--hard-limit-db", "-10", "--startup-volume-db", "-5"]).unwrap();
        let limit = require_hard_limit(&a).unwrap();
        let clamped = proto::volume_packet(post_switch_volume_db(&a), limit, 0, 0);
        let expected = proto::volume_packet(-10.0, limit, 0, 0);
        assert_eq!(clamped, expected);
        // And a startup volume below the limit is passed through untouched.
        let b = args(&["--ip", "1.2.3.4", "source", "0", "--hard-limit-db", "-10", "--startup-volume-db", "-33"]).unwrap();
        assert_eq!(
            proto::volume_packet(post_switch_volume_db(&b), limit, 0, 0),
            proto::volume_packet(-33.0, None, 0, 0)
        );
    }
}
