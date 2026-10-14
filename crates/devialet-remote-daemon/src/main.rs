//! Status-listener daemon. Owns the UDP 45454 socket, parses every status
//! broadcast via `devialet_protocol`, and pushes the latest state out over
//! the session bus (`com.ekmanch.DevialetRemote`, see interface.rs) with
//! `PropertiesChanged` signals - no polling, no status file. Architecture:
//! docs/DESIGN.md §1, D-Bus surface: §2.
//!
//! Every amp heard broadcasting is tracked, with an explicit selection on
//! top; all tracking/selection/staleness logic lives in `AmpState`
//! (interface.rs). This file is only the I/O shim: receive loop, D-Bus
//! registration, mDNS.
//!
//! Model names are resolved over mDNS, best-effort, with one continuous
//! `browse()` session started at startup for the process lifetime and
//! never restarted. `mdns-sd` re-queries cached records itself as their
//! TTL nears expiry (RFC 6762 §7.1), so no manual refresh is needed.
//! `ServiceResolved` events are drained non-blockingly and matched to
//! known amps by IP; a resolved name is never re-attempted or cleared.

mod config;
mod interface;

use devialet_protocol as proto;
use interface::AmpState;
use mdns_sd::{ServiceDaemon, ServiceEvent};
use socket2::{Domain, Protocol, Socket, Type};
use std::net::{SocketAddr, UdpSocket};
use std::time::Duration;

/// Not Devialet-specific; `resolve_model_name` only trusts a match for an
/// amp already heard over UDP. `browse()` requires the `._tcp.local.`
/// suffix.
const MDNS_SERVICE_TYPE: &str = "_spotify-connect._tcp.local.";

/// Read timeout of the blocking receive loop. Without it an indefinite
/// `recv_from` would never wake to notice an amp going silent; the tick
/// also drives the boot and pending-command deadlines in `AmpState`.
const POLL_TICK: Duration = Duration::from_secs(1);

fn bind_status_socket() -> std::io::Result<UdpSocket> {
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    let addr: SocketAddr = ([0, 0, 0, 0], proto::STATUS_PORT).into();
    socket.bind(&addr.into())?;
    socket.set_broadcast(true)?;
    socket.set_read_timeout(Some(POLL_TICK))?;
    Ok(socket.into())
}

/// Set `DEVIALET_DAEMON_DEBUG=1` to enable verbose per-packet diagnostics:
/// every `recv_from` outcome, a full hex dump of the first few real packets
/// received, parse success/failure detail, and a read-back check proving
/// the property getters see the same state the receive loop just wrote.
/// Off by default: the amp broadcasts at ~1-5 Hz.
fn debug_enabled() -> bool {
    std::env::var("DEVIALET_DAEMON_DEBUG").as_deref() == Ok("1")
}

fn hex_dump(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" ")
}

/// Starts the mDNS browse session for model-name resolution. Cosmetic
/// only: on any setup failure this logs and returns `None`, and the
/// daemon runs with raw UDP device names. Never a fatal startup error.
fn start_mdns_browse() -> Option<mdns_sd::Receiver<ServiceEvent>> {
    let daemon = match ServiceDaemon::new() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("mDNS: failed to start service daemon, model name resolution disabled: {e}");
            return None;
        }
    };
    match daemon.browse(MDNS_SERVICE_TYPE) {
        Ok(receiver) => {
            eprintln!("mDNS: browsing {MDNS_SERVICE_TYPE} for amp model name resolution");
            Some(receiver)
        }
        Err(e) => {
            eprintln!("mDNS: failed to browse {MDNS_SERVICE_TYPE}, model name resolution disabled: {e}");
            None
        }
    }
}

/// Drains every queued mDNS event without blocking (`try_recv`). Called on
/// every main-loop iteration, not only on a `POLL_TICK` timeout, so a
/// steady stream of UDP packets cannot starve it.
fn drain_mdns_events(
    receiver: &mdns_sd::Receiver<ServiceEvent>,
    iface_ref: &zbus::blocking::object_server::InterfaceRef<AmpState>,
    debug: bool,
) -> zbus::Result<()> {
    loop {
        let event = match receiver.try_recv() {
            Ok(event) => event,
            Err(_) => return Ok(()), // Empty (or the daemon thread exited) - nothing more to do right now.
        };
        let ServiceEvent::ServiceResolved(resolved) = event else {
            continue;
        };

        // IPv4 only: `AmpState::amps` is keyed by the IPv4 source address
        // of the status socket, so an IPv6 address could never match.
        let Some(ip) = resolved.addresses.iter().find(|addr| addr.is_ipv4()).map(|addr| addr.to_ip_addr().to_string()) else {
            continue;
        };
        let Some(model_name) = proto::parse_model_name(&resolved.host) else {
            continue;
        };

        let mut iface = iface_ref.get_mut();
        let before = iface.clone();
        let applied = iface.resolve_model_name(&ip, model_name.clone());
        if debug {
            eprintln!(
                "[debug] mDNS: resolved host={:?} -> ip={ip} model_name={model_name:?} (matched a known amp: {applied})",
                resolved.host
            );
        }
        if applied {
            emit_if_changed(iface_ref, &iface, &before)?;
        }
    }
}

fn main() -> std::io::Result<()> {
    let debug = debug_enabled();

    eprintln!(
        "devialet-remote-daemon starting: status UDP {}, D-Bus name {}",
        proto::STATUS_PORT,
        interface::BUS_NAME
    );
    if debug {
        eprintln!("[debug] DEVIALET_DAEMON_DEBUG=1: verbose diagnostics on");
    }
    // The receive loop runs on main() itself; this binary spawns no
    // thread. A panic kills the whole process, D-Bus name included, so a
    // daemon answering on D-Bus with frozen state is not a dead thread.
    eprintln!("receive loop runs on main() directly - no spawned thread in this binary");

    // Apply any persisted selection before the object server starts, so
    // no signal is needed. `None` (nothing ever persisted) leaves
    // `has_explicit_selection` false, so auto-select-if-alone applies.
    let mut initial_state = AmpState::default();
    match config::load_selected_ip() {
        Some(ip) => {
            eprintln!("config: restoring persisted amp selection: {:?}", if ip.is_empty() { "<none>" } else { &ip });
            initial_state.set_persisted_selection(ip);
        }
        None => eprintln!("config: no persisted amp selection found, starting with none"),
    }

    let connection = zbus::blocking::connection::Builder::session()
        .and_then(|b| b.serve_at(interface::OBJECT_PATH, initial_state))
        .and_then(|b| b.name(interface::BUS_NAME))
        .and_then(|b| b.build())
        .map_err(std::io::Error::other)?;

    let iface_ref: zbus::blocking::object_server::InterfaceRef<AmpState> = connection
        .object_server()
        .interface(interface::OBJECT_PATH)
        .map_err(std::io::Error::other)?;

    eprintln!(
        "registered {} at {} on {}",
        interface::INTERFACE_NAME,
        interface::OBJECT_PATH,
        interface::BUS_NAME
    );

    let socket = bind_status_socket()?;
    eprintln!("listening for status broadcasts on 0.0.0.0:{}", proto::STATUS_PORT);

    let mdns_receiver = start_mdns_browse();

    let mut packets_seen: u64 = 0;

    let mut buf = [0u8; 2048];
    loop {
        // Every iteration, not only on timeout - see drain_mdns_events.
        if let Some(receiver) = &mdns_receiver {
            drain_mdns_events(receiver, &iface_ref, debug).map_err(std::io::Error::other)?;
        }

        match socket.recv_from(&mut buf) {
            Ok((len, src)) => {
                packets_seen += 1;
                if debug {
                    eprintln!("[debug] recv_from: Ok, {len} bytes from {src} (packet #{packets_seen})");
                }
                // Raw bytes of the first few packets, to check against
                // docs/protocol.md's offsets and minimum length.
                if debug && packets_seen <= 3 {
                    eprintln!("[debug] raw bytes (packet #{packets_seen}, {len} bytes):\n{}", hex_dump(&buf[..len]));
                }

                let parse_result = proto::parse_status(&buf[..len]);
                if debug {
                    match &parse_result {
                        Ok(s) => eprintln!(
                            "[debug] parse_status: Ok - device_name={:?} power={} muted={} volume_raw={} source_index={}",
                            s.device_name, s.power_on, s.muted, s.volume_raw, s.source_index
                        ),
                        Err(e) => eprintln!("[debug] parse_status: Err({e:?}) for a {len}-byte packet (STATUS_MIN_LEN={})", proto::STATUS_MIN_LEN),
                    }
                }

                let Ok(status) = parse_result else {
                    // Too short or malformed: drop it and keep listening.
                    continue;
                };
                let ip = src.ip().to_string();
                let device_name = status.device_name.clone();

                ingest_and_maybe_emit(&iface_ref, ip.clone(), status).map_err(std::io::Error::other)?;

                // Read back through the same InterfaceRef the property
                // getters use, to show they see this write. The values are
                // the primary amp's, which may not be this packet's amp.
                if debug {
                    let read_back = iface_ref.get();
                    eprintln!(
                        "[debug] read-back via iface_ref.get() immediately after write: primary device_name={:?} online={} (packet was from {ip:?}, device_name={device_name:?})",
                        read_back.device_name(), read_back.online()
                    );
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock || e.kind() == std::io::ErrorKind::TimedOut => {
                if debug {
                    eprintln!("[debug] recv_from: timed out (no packet in {POLL_TICK:?}) - loop is alive, {packets_seen} real packets seen so far");
                }
                // No packet within POLL_TICK: re-check staleness for every
                // known amp, since KnownAmps reports non-primary ones too.
                recompute_staleness_and_maybe_emit(&iface_ref).map_err(std::io::Error::other)?;
            }
            Err(e) => {
                // Treated as transient; keep looping.
                eprintln!("recv_from error (continuing): {e}");
            }
        }
    }
}

/// Records a freshly parsed status broadcast and emits `PropertiesChanged`
/// only if an exposed property actually changed; otherwise every packet
/// from a non-primary amp would cause a no-op emit.
fn ingest_and_maybe_emit(
    iface_ref: &zbus::blocking::object_server::InterfaceRef<AmpState>,
    ip: String,
    status: proto::Status,
) -> zbus::Result<()> {
    let mut iface = iface_ref.get_mut();
    let before = iface.clone();
    iface.ingest_status(ip, status);
    emit_if_changed(iface_ref, &iface, &before)
}

/// Re-derives staleness and deadlines with no new packet and emits only if
/// something changed. Driven by `POLL_TICK`.
fn recompute_staleness_and_maybe_emit(
    iface_ref: &zbus::blocking::object_server::InterfaceRef<AmpState>,
) -> zbus::Result<()> {
    let mut iface = iface_ref.get_mut();
    let before = iface.clone();
    iface.recompute_staleness();
    emit_if_changed(iface_ref, &iface, &before)
}

fn emit_if_changed(
    iface_ref: &zbus::blocking::object_server::InterfaceRef<AmpState>,
    iface: &AmpState,
    before: &AmpState,
) -> zbus::Result<()> {
    if interface::states_equal(before, iface) {
        return Ok(());
    }
    let emitter = iface_ref.signal_emitter();
    async_io::block_on(interface::emit_all(iface, emitter))
}
