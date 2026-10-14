use crate::config;
use devialet_protocol as proto;
use std::collections::HashMap;
use std::net::Ipv4Addr;
use std::time::{Duration, Instant};
use zbus::interface;

pub const BUS_NAME: &str = "com.ekmanch.DevialetRemote";
pub const OBJECT_PATH: &str = "/com/ekmanch/DevialetRemote/Amp";
pub const INTERFACE_NAME: &str = "com.ekmanch.DevialetRemote.Amp1";

/// How long after `BeginPowerOnBoot` the daemon waits for a broadcast
/// confirming `power_on = true` before reporting `PowerState = "Off"`
/// again (see `resolve_boot_deadlines`). Silent fallback, no error state:
/// boot failures have not been observed.
///
/// 20 s: one measured boot of an Expert 140 Pro took ~16.07 s
/// (`BeginPowerOnBoot` to UDP confirmation); 15 s flashed "Off" for about
/// a second before "On".
const BOOT_TIMEOUT: Duration = Duration::from_secs(20);

/// How long a `NotifyVolumeCommand`/`NotifyMuteCommand` value is shown
/// before falling back to the amp's last-known status, absent a
/// confirming broadcast (see `resolve_pending_commands`). 400 ms is the
/// window the Kotlin app, the Flutter port and the widget's QML use to
/// keep a stale in-flight broadcast from contradicting a just-sent
/// command (docs/DESIGN.md §3, docs/known-gotchas.md #1).
const PENDING_COMMAND_TIMEOUT: Duration = Duration::from_millis(400);

/// One amp's last-known status broadcast, keyed by IP in `AmpState::amps`.
/// Never evicted once seen; staleness is derived from `last_seen`.
#[derive(Debug, Clone)]
struct TrackedAmp {
    status: proto::Status,
    last_seen: Instant,
    /// Resolved via mDNS; `None` until resolution succeeds. Once set,
    /// never cleared. Like every field below, carried forward by
    /// `ingest_status`: rebuilding the entry on each broadcast would
    /// otherwise wipe it.
    model_name: Option<String>,
    /// Set by `BeginPowerOnBoot`, cleared by `resolve_boot_deadlines` once
    /// `power_on = true` is confirmed or `BOOT_TIMEOUT` elapses. `Some`
    /// makes `PowerState` report "Booting" whatever `power_on` says.
    boot_deadline: Option<Instant>,
    /// `(requested_db, deadline)`, set by `NotifyVolumeCommand`, cleared by
    /// `resolve_pending_commands` once a broadcast confirms
    /// `status.volume_db() == requested_db` or `PENDING_COMMAND_TIMEOUT`
    /// elapses. `Some` makes `VolumeDb` report the requested value instead
    /// of the amp's last-known one.
    pending_volume_db: Option<(f64, Instant)>,
    /// `NotifyMuteCommand`'s equivalent of `pending_volume_db`, confirmed
    /// against `status.muted`.
    pending_muted: Option<(bool, Instant)>,
}

/// D-Bus-exposed state: the "primary amp" properties plus the multi-amp
/// discovery/selection surface (docs/DESIGN.md §2).
///
/// `amps` holds every amp ever heard, keyed by IP. `selected_ip` is the
/// explicit selection (`""` = none). When nothing has ever been chosen and
/// exactly one amp is known, that amp drives the primary properties (see
/// `effective_ip`); with zero or 2+ known amps they show the empty
/// "not connected" state instead of guessing.
///
/// "Never chosen" and "explicitly chose None" both leave `selected_ip`
/// empty, so `has_explicit_selection` tells them apart. Without it,
/// `SelectAmp("")` would be overridden by auto-select-if-alone, and a
/// persisted "None" would be undone on every restart.
#[derive(Debug, Clone, Default)]
pub struct AmpState {
    amps: HashMap<String, TrackedAmp>,
    selected_ip: String,
    /// True once `SelectAmp` has been called (any ip, including "") or a
    /// selection was loaded from disk; false only when nothing has ever
    /// been chosen. See the struct doc.
    has_explicit_selection: bool,
    /// Boot deadlines for IPs with no `TrackedAmp` entry yet: a
    /// `BeginPowerOnBoot` for the persisted selection before that amp has
    /// been heard since daemon start. Without this the call had nowhere to
    /// store a deadline, `PowerState` never left "Off" and the widget's
    /// optimistic "Booting" never ended. Moved onto the entry by
    /// `ingest_status` on the amp's first broadcast, dropped by
    /// `resolve_boot_deadlines` at `BOOT_TIMEOUT`.
    unheard_boot_deadlines: HashMap<String, Instant>,

    // ---- exposed fields below, all derived from the fields above by
    // `recompute()` - never written to directly outside of it. ----
    device_name: String,
    amp_ip: String,
    online: bool,
    power: bool,
    /// `"Off"` / `"Booting"` / `"On"`, alongside `power` (see the
    /// `PowerState` property doc). Empty only before the first
    /// `recompute()`.
    power_state: String,
    muted: bool,
    volume_raw: u8,
    volume_db: f64,
    active_source_index: u8,
    active_source_name: String,
    sources: Vec<(String, u8, bool, bool)>,
    known_amps: Vec<(String, String, bool, String)>,
}

#[interface(name = "com.ekmanch.DevialetRemote.Amp1")]
impl AmpState {
    #[zbus(property, name = "DeviceName")]
    pub fn device_name(&self) -> String {
        self.device_name.clone()
    }

    #[zbus(property, name = "AmpIp")]
    pub fn amp_ip(&self) -> String {
        self.amp_ip.clone()
    }

    /// Whether the *selected* (or auto-selected, see struct doc) amp has
    /// been heard from within `devialet_protocol::STALE_AFTER` (8s). False
    /// when nothing is selected/auto-selected at all, not just when the
    /// selected amp goes quiet.
    #[zbus(property, name = "Online")]
    pub fn online(&self) -> bool {
        self.online
    }

    #[zbus(property, name = "Power")]
    pub fn power(&self) -> bool {
        self.power
    }

    /// `"Off"` / `"Booting"` / `"On"`. `Power` stays the amp's raw UDP
    /// `power_on` bit; `PowerState` adds the "Booting" window started by
    /// `BeginPowerOnBoot` and ended by `resolve_boot_deadlines`.
    #[zbus(property, name = "PowerState")]
    pub fn power_state(&self) -> String {
        self.power_state.clone()
    }

    #[zbus(property, name = "Muted")]
    pub fn muted(&self) -> bool {
        self.muted
    }

    /// Raw 0-255 status byte, never masked by a pending command (see
    /// `recompute`).
    #[zbus(property, name = "VolumeRaw")]
    pub fn volume_raw(&self) -> u8 {
        self.volume_raw
    }

    #[zbus(property, name = "VolumeDb")]
    pub fn volume_db(&self) -> f64 {
        self.volume_db
    }

    #[zbus(property, name = "ActiveSourceIndex")]
    pub fn active_source_index(&self) -> u8 {
        self.active_source_index
    }

    #[zbus(property, name = "ActiveSourceName")]
    pub fn active_source_name(&self) -> String {
        self.active_source_name.clone()
    }

    /// Full 30-slot source table (name, index, enabled, selected) for the
    /// selected/auto-selected amp - see struct doc. Empty (not 30 blank
    /// entries) when nothing is selected/auto-selected, distinguishing "no
    /// amp" from "a real amp with mostly-disabled slots".
    #[zbus(property, name = "Sources")]
    pub fn sources(&self) -> Vec<(String, u8, bool, bool)> {
        self.sources.clone()
    }

    /// Every amp ever heard broadcasting, as `(ip, device_name, online,
    /// model_name)`. `device_name` is always the raw UDP name (unlike
    /// `DeviceName`), so a picker can show both. `online` uses the same 8 s
    /// rule as `Online`. `model_name` is `""` until mDNS resolves it and is
    /// never cleared. Never pruned: a gone amp stays with `online = false`,
    /// and filtering is left to the client. Sorted numerically by IP
    /// (`192.168.0.9` before `192.168.0.10`), so the order only changes
    /// when a new amp is first heard.
    #[zbus(property, name = "KnownAmps")]
    pub fn known_amps(&self) -> Vec<(String, String, bool, String)> {
        self.known_amps.clone()
    }

    /// Explicitly selected amp's IP, or "" if none. Stays "" while
    /// auto-select-if-alone (see struct doc) drives the primary properties.
    #[zbus(property, name = "SelectedAmpIp")]
    pub fn selected_amp_ip(&self) -> String {
        self.selected_ip.clone()
    }

    /// Selects an amp by IP for the primary properties; "" explicitly
    /// clears the selection. Accepts an IP never heard yet (manual entry):
    /// the primary properties then show that IP as not connected until a
    /// broadcast from it arrives.
    ///
    /// Always sets `has_explicit_selection`, even for "" (see struct doc),
    /// and persists `ip` via `config::save_selected_ip`. Persistence is
    /// best-effort; a write failure never fails this call.
    #[zbus(name = "SelectAmp")]
    async fn select_amp(
        &mut self,
        ip: String,
        #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let before = self.clone();
        config::save_selected_ip(&ip);
        self.selected_ip = ip;
        self.has_explicit_selection = true;
        self.recompute();
        if !states_equal(&before, self) {
            emit_all(self, &emitter)
                .await
                .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        }
        Ok(())
    }

    /// Marks `ip` as booting. `PowerState` reports "Booting" for it (once
    /// it is the effective amp) until a broadcast confirms `Power = true`
    /// or `BOOT_TIMEOUT` (20 s) elapses. Resolved by
    /// `resolve_boot_deadlines` on the next `recompute()`, which every
    /// packet and the receive loop's 1 s tick trigger, so no timer is
    /// needed.
    ///
    /// An `ip` not heard since daemon start gets the same timeout through
    /// `unheard_boot_deadlines`.
    ///
    /// No-op (no state change, no signal) while a boot is already in
    /// progress for `ip`: the deadline is not reset, so repeated calls
    /// cannot keep an amp "Booting" indefinitely. The widget also disables
    /// the power button while booting; this guard covers races.
    #[zbus(name = "BeginPowerOnBoot")]
    async fn begin_power_on_boot(
        &mut self,
        ip: String,
        #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let before = self.clone();
        match self.amps.get_mut(&ip) {
            Some(amp) if amp.boot_deadline.is_none() => {
                amp.boot_deadline = Some(Instant::now() + BOOT_TIMEOUT);
            }
            Some(_) => return Ok(()), // a boot is already in progress - no-op
            None => {
                if !self.begin_unheard_boot(ip) {
                    return Ok(()); // a boot is already in progress - no-op
                }
            }
        }
        self.recompute();
        if !states_equal(&before, self) {
            emit_all(self, &emitter)
                .await
                .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        }
        Ok(())
    }

    /// Records that a volume command for `db` was just sent to `ip`;
    /// `VolumeDb` reports it until the amp confirms it or
    /// `PENDING_COMMAND_TIMEOUT` passes (docs/DESIGN.md §3). Called from
    /// QML next to the `devialet-ctl` invocation; the CLI itself never
    /// talks to the daemon.
    ///
    /// No-op only for an `ip` with no `TrackedAmp` entry. Otherwise every
    /// call replaces the pending value and resets its deadline, so a rapid
    /// series of commands settles on the most recent one.
    ///
    /// Then emits `VolumeCommandNotified(ip, db)` unconditionally (not
    /// gated on `states_equal`), after the `PropertiesChanged` burst so a
    /// handler already sees this call's property values. It marks "a
    /// command was sent", which lets the widget show its OSD for commands
    /// from other tools (e.g. the MPV script). Watching `VolumeDb` cannot
    /// do that: it also changes for adjustments only observed from the
    /// amp (physical remote), which must show nothing. The signal carries
    /// the value, so it needs no `Get` and still fires when the value is
    /// unchanged. The widget filters its own echoes in
    /// `PendingAmpState.qml`.
    #[zbus(name = "NotifyVolumeCommand")]
    async fn notify_volume_command(
        &mut self,
        ip: String,
        db: f64,
        #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let before = self.clone();
        let Some(amp) = self.amps.get_mut(&ip) else {
            return Ok(()); // unknown ip - no-op, mirrors begin_power_on_boot
        };
        amp.pending_volume_db = Some((db, Instant::now() + PENDING_COMMAND_TIMEOUT));
        self.recompute();
        if !states_equal(&before, self) {
            emit_all(self, &emitter)
                .await
                .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        }
        Self::volume_command_notified(&emitter, &ip, db)
            .await
            .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        Ok(())
    }

    /// `NotifyVolumeCommand`'s equivalent for mute: `Muted`/`pending_muted`
    /// and `MuteCommandNotified(ip, muted)`, under the same rules.
    #[zbus(name = "NotifyMuteCommand")]
    async fn notify_mute_command(
        &mut self,
        ip: String,
        muted: bool,
        #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let before = self.clone();
        let Some(amp) = self.amps.get_mut(&ip) else {
            return Ok(()); // unknown ip - no-op, mirrors begin_power_on_boot
        };
        amp.pending_muted = Some((muted, Instant::now() + PENDING_COMMAND_TIMEOUT));
        self.recompute();
        if !states_equal(&before, self) {
            emit_all(self, &emitter)
                .await
                .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        }
        Self::mute_command_notified(&emitter, &ip, muted)
            .await
            .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        Ok(())
    }

    /// `VolumeCommandNotified(s ip, d db)`: emitted by `NotifyVolumeCommand`
    /// for every accepted call. The only custom signals on this interface;
    /// everything else is `PropertiesChanged`. Bodiless per zbus 5's
    /// `#[zbus(signal)]` form; the macro generates the body.
    #[zbus(signal, name = "VolumeCommandNotified")]
    async fn volume_command_notified(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        ip: &str,
        db: f64,
    ) -> zbus::Result<()>;

    /// `MuteCommandNotified(s ip, b muted)`: `NotifyMuteCommand`'s
    /// counterpart of `VolumeCommandNotified` above.
    #[zbus(signal, name = "MuteCommandNotified")]
    async fn mute_command_notified(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        ip: &str,
        muted: bool,
    ) -> zbus::Result<()>;
}

impl AmpState {
    /// Records a freshly-received, already-parsed status broadcast from
    /// `ip` and re-derives every exposed field. Called once per real UDP
    /// packet from the daemon's receive loop.
    pub fn ingest_status(&mut self, ip: String, status: proto::Status) {
        // Carry the per-amp extras forward (see `TrackedAmp`): a naive
        // overwrite would wipe them on the next broadcast (up to ~5 Hz).
        let model_name = self.amps.get(&ip).and_then(|amp| amp.model_name.clone());
        // A deadline started before this amp was ever heard moves onto its
        // entry here (see `unheard_boot_deadlines`).
        let boot_deadline =
            self.amps.get(&ip).and_then(|amp| amp.boot_deadline).or(self.unheard_boot_deadlines.remove(&ip));
        // Pending commands must survive so `recompute` can compare the new
        // status against them.
        let pending_volume_db = self.amps.get(&ip).and_then(|amp| amp.pending_volume_db);
        let pending_muted = self.amps.get(&ip).and_then(|amp| amp.pending_muted);
        self.amps.insert(
            ip,
            TrackedAmp { status, last_seen: Instant::now(), model_name, boot_deadline, pending_volume_db, pending_muted },
        );
        self.recompute();
    }

    /// Applies an mDNS-resolved model name to a known amp (one already heard
    /// over UDP) and re-derives every exposed field. Returns `false`
    /// without change for an unknown `ip`: the browsed service type
    /// (`_spotify-connect._tcp`) is not Devialet-specific, so a name must
    /// never be trusted for an IP not heard speaking the Devialet protocol.
    pub fn resolve_model_name(&mut self, ip: &str, model_name: String) -> bool {
        let Some(amp) = self.amps.get_mut(ip) else {
            return false;
        };
        amp.model_name = Some(model_name);
        self.recompute();
        true
    }

    /// `BeginPowerOnBoot`'s path for an `ip` with no `TrackedAmp` entry -
    /// see `unheard_boot_deadlines`. Returns `false` (nothing changed) if
    /// a boot is already pending for it, so a repeated call can't extend
    /// the deadline, same as the tracked-amp path.
    fn begin_unheard_boot(&mut self, ip: String) -> bool {
        if self.unheard_boot_deadlines.contains_key(&ip) {
            return false;
        }
        self.unheard_boot_deadlines.insert(ip, Instant::now() + BOOT_TIMEOUT);
        true
    }

    /// Applies a selection loaded from disk at startup, before the D-Bus
    /// object server exists, so no signal is emitted. Called at most once,
    /// from `main()`.
    ///
    /// `ip` may be `""` (a persisted explicit "None"), and
    /// `has_explicit_selection` is set either way; otherwise a persisted
    /// "None" would be undone by auto-select-if-alone on every restart.
    ///
    /// Inserts no `TrackedAmp` for `ip`: until a real broadcast arrives,
    /// `recompute()` finds no entry and the primary properties show the
    /// not-connected state with `AmpIp` set.
    pub fn set_persisted_selection(&mut self, ip: String) {
        self.selected_ip = ip;
        self.has_explicit_selection = true;
        self.recompute();
    }

    /// Re-derives every exposed field with no new packet. Called on each
    /// receive-loop tick, so an amp going quiet is reflected in `Online`
    /// and `KnownAmps`, and the boot and pending-command deadlines get
    /// checked without a dedicated timer.
    pub fn recompute_staleness(&mut self) {
        self.recompute();
    }

    /// The IP whose status drives the primary properties: the explicit
    /// selection if any, else the sole known amp if there is exactly one
    /// and nothing has ever been explicitly selected (including "None"),
    /// else nothing. See the struct doc.
    fn effective_ip(&self) -> Option<String> {
        if !self.selected_ip.is_empty() {
            return Some(self.selected_ip.clone());
        }
        if !self.has_explicit_selection && self.amps.len() == 1 {
            return self.amps.keys().next().cloned();
        }
        None
    }

    /// Clears every boot deadline that has resolved: `power_on = true`
    /// confirmed, or `BOOT_TIMEOUT` elapsed. A timed-out boot needs no
    /// special case: with the deadline gone and `power_on` false,
    /// `recompute` reports "Off". Runs for every amp, not just the primary.
    fn resolve_boot_deadlines(&mut self) {
        let now = Instant::now();
        for amp in self.amps.values_mut() {
            if let Some(deadline) = amp.boot_deadline {
                if amp.status.power_on || now >= deadline {
                    amp.boot_deadline = None;
                }
            }
        }
        self.unheard_boot_deadlines.retain(|_, deadline| now < *deadline);
    }

    /// Clears `pending_volume_db`/`pending_muted` for every tracked amp
    /// once a broadcast confirms the value or `PENDING_COMMAND_TIMEOUT`
    /// elapses. Runs for every amp, not just the primary.
    ///
    /// Exact equality, no epsilon: `Status::volume_db()` is
    /// `(volume_raw - 195) / 2.0` and the widget only sends 0.5 dB steps
    /// (`volumeStepDb` is 0.5/1/2), so both sides are exact multiples of
    /// 0.5.
    fn resolve_pending_commands(&mut self) {
        let now = Instant::now();
        for amp in self.amps.values_mut() {
            if let Some((pending_db, deadline)) = amp.pending_volume_db {
                if amp.status.volume_db() == pending_db || now >= deadline {
                    amp.pending_volume_db = None;
                }
            }
            if let Some((pending_muted, deadline)) = amp.pending_muted {
                if amp.status.muted == pending_muted || now >= deadline {
                    amp.pending_muted = None;
                }
            }
        }
    }

    fn recompute(&mut self) {
        self.resolve_boot_deadlines();
        self.resolve_pending_commands();

        let mut known_amps: Vec<(String, String, bool, String)> = self
            .amps
            .iter()
            .map(|(ip, amp)| {
                (
                    ip.clone(),
                    amp.status.device_name.clone(),
                    amp.last_seen.elapsed() < proto::STALE_AFTER,
                    amp.model_name.clone().unwrap_or_default(),
                )
            })
            .collect();
        // Numeric (octet-wise), not lexicographic: a string sort puts
        // "192.168.0.10" before "192.168.0.9". IPs in `amps` always come
        // from the IPv4-only status socket, so a parse failure means that
        // invariant broke.
        known_amps.sort_by_key(|(ip, _, _, _)| {
            ip.parse::<Ipv4Addr>()
                .expect("amp IPs are always valid IPv4 dotted-quads - see bind_status_socket")
        });
        self.known_amps = known_amps;

        let effective_ip = self.effective_ip();
        self.amp_ip = effective_ip.clone().unwrap_or_default();

        // Selected but never heard: "Booting" only while a deadline from
        // `begin_unheard_boot` is pending for it.
        let unheard_booting =
            effective_ip.as_ref().is_some_and(|ip| self.unheard_boot_deadlines.contains_key(ip));

        match effective_ip.and_then(|ip| self.amps.get(&ip)) {
            Some(amp) => {
                // The resolved model name if known, else the raw UDP name
                // (which `KnownAmps` always carries).
                self.device_name = amp
                    .model_name
                    .clone()
                    .filter(|name| !name.is_empty())
                    .unwrap_or_else(|| amp.status.device_name.clone());
                self.online = amp.last_seen.elapsed() < proto::STALE_AFTER;
                self.power = amp.status.power_on;
                self.power_state = if amp.boot_deadline.is_some() {
                    "Booting"
                } else if amp.status.power_on {
                    "On"
                } else {
                    "Off"
                }
                .to_string();
                // A live pending command wins over the amp's last-known
                // status. `VolumeRaw` deliberately stays unmasked:
                // PendingAmpState.qml's post-boot hold confirms against it
                // because it reflects only what the amp reports.
                self.muted = amp.pending_muted.map(|(v, _)| v).unwrap_or(amp.status.muted);
                self.volume_raw = amp.status.volume_raw;
                self.volume_db = amp.pending_volume_db.map(|(v, _)| v).unwrap_or_else(|| amp.status.volume_db());
                self.active_source_index = amp.status.source_index;
                self.active_source_name = amp.status.current_source_name().unwrap_or("").to_string();
                self.sources = amp
                    .status
                    .sources
                    .iter()
                    .map(|s| (s.name.clone(), s.index, s.enabled, s.selected))
                    .collect();
            }
            None => {
                self.device_name = String::new();
                self.online = false;
                self.power = false;
                self.power_state = if unheard_booting { "Booting" } else { "Off" }.to_string();
                self.muted = false;
                self.volume_raw = 0;
                self.volume_db = 0.0;
                self.active_source_index = 0;
                self.active_source_name = String::new();
                self.sources = Vec::new();
            }
        }
    }
}

/// Compares every exposed field, excluding `amps` (its timestamps change
/// every tick), to decide whether a `PropertiesChanged` round is needed.
pub(crate) fn states_equal(a: &AmpState, b: &AmpState) -> bool {
    a.device_name == b.device_name
        && a.amp_ip == b.amp_ip
        && a.online == b.online
        && a.power == b.power
        && a.power_state == b.power_state
        && a.muted == b.muted
        && a.volume_raw == b.volume_raw
        && a.volume_db == b.volume_db
        && a.active_source_index == b.active_source_index
        && a.active_source_name == b.active_source_name
        && a.sources == b.sources
        && a.known_amps == b.known_amps
        && a.selected_ip == b.selected_ip
}

/// Emits `PropertiesChanged` for every property unconditionally; callers
/// gate it on `states_equal`. Used by the receive loop (main.rs) and the
/// D-Bus methods above.
pub async fn emit_all(state: &AmpState, emitter: &zbus::object_server::SignalEmitter<'_>) -> zbus::Result<()> {
    state.device_name_changed(emitter).await?;
    state.amp_ip_changed(emitter).await?;
    state.online_changed(emitter).await?;
    state.power_changed(emitter).await?;
    state.power_state_changed(emitter).await?;
    state.muted_changed(emitter).await?;
    state.volume_raw_changed(emitter).await?;
    state.volume_db_changed(emitter).await?;
    state.active_source_index_changed(emitter).await?;
    state.active_source_name_changed(emitter).await?;
    state.sources_changed(emitter).await?;
    state.known_amps_changed(emitter).await?;
    state.selected_amp_ip_changed(emitter).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use devialet_protocol::fixtures::StatusFixtureBuilder;

    /// Builds bytes with the protocol crate's fixture builder and parses
    /// them with the real `parse_status`, rather than a `Status` literal.
    fn parsed_status(device_name: &str) -> proto::Status {
        let bytes = StatusFixtureBuilder::new()
            .device_name(device_name)
            .source(0, "Optical 1", true)
            .active_source_index(0)
            .power(true)
            .volume_raw(195)
            .build();
        proto::parse_status(&bytes).expect("fixture packet should parse")
    }

    /// `parsed_status` with `power_on = false`, as an amp mid-boot reports.
    fn parsed_status_off(device_name: &str) -> proto::Status {
        let bytes = StatusFixtureBuilder::new()
            .device_name(device_name)
            .source(0, "Optical 1", true)
            .active_source_index(0)
            .power(false)
            .volume_raw(195)
            .build();
        proto::parse_status(&bytes).expect("fixture packet should parse")
    }

    #[test]
    fn two_distinct_amps_are_tracked_as_separate_known_amps_entries() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        state.ingest_status("192.168.1.51".to_string(), parsed_status("Bedroom Amp"));

        assert_eq!(state.known_amps.len(), 2, "second amp must not overwrite the first");
        let mut names: Vec<&str> = state.known_amps.iter().map(|(_, name, _, _)| name.as_str()).collect();
        names.sort();
        assert_eq!(names, vec!["Bedroom Amp", "Living Room Amp"]);
        assert!(state.known_amps.iter().all(|(_, _, online, _)| *online), "freshly-ingested amps are online");
    }

    #[test]
    fn re_ingesting_the_same_ip_updates_in_place_rather_than_duplicating() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Renamed Amp"));

        assert_eq!(state.known_amps.len(), 1);
        assert_eq!(state.known_amps[0].1, "Renamed Amp");
    }

    #[test]
    fn with_exactly_one_known_amp_and_no_explicit_selection_it_is_auto_selected() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));

        assert_eq!(state.selected_ip, "", "auto-select must not itself set an explicit selection");
        assert_eq!(state.device_name, "Living Room Amp");
        assert_eq!(state.amp_ip, "192.168.1.50");
        assert!(state.online);
    }

    #[test]
    fn with_two_known_amps_and_no_explicit_selection_primary_falls_back_to_not_connected() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        state.ingest_status("192.168.1.51".to_string(), parsed_status("Bedroom Amp"));

        assert_eq!(state.device_name, "");
        assert_eq!(state.amp_ip, "");
        assert!(!state.online);
        assert!(state.sources.is_empty());
        // The discovery list itself is unaffected by there being no primary.
        assert_eq!(state.known_amps.len(), 2);
    }

    #[test]
    fn explicit_selection_picks_the_named_amp_regardless_of_known_amp_count() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        state.ingest_status("192.168.1.51".to_string(), parsed_status("Bedroom Amp"));

        state.selected_ip = "192.168.1.51".to_string();
        state.recompute();

        assert_eq!(state.device_name, "Bedroom Amp");
        assert_eq!(state.amp_ip, "192.168.1.51");
        assert!(state.online);
    }

    #[test]
    fn explicit_selection_of_an_unknown_ip_shows_the_ip_but_not_connected() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));

        state.selected_ip = "192.168.1.99".to_string();
        state.recompute();

        assert_eq!(state.amp_ip, "192.168.1.99");
        assert_eq!(state.device_name, "");
        assert!(!state.online);
    }

    // SelectAmp("") must not fall back to auto-select-if-alone. The async
    // `select_amp` cannot be called without a zbus context, so this sets
    // `selected_ip` and `has_explicit_selection` together by hand, as
    // `select_amp` does.
    #[test]
    fn explicit_none_selection_does_not_fall_back_to_auto_select() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        state.selected_ip = "192.168.1.50".to_string();
        state.has_explicit_selection = true;
        state.recompute();
        assert_eq!(state.device_name, "Living Room Amp");

        // Explicitly clearing back to "" - matches what a real
        // SelectAmp("") call does.
        state.selected_ip = String::new();
        state.has_explicit_selection = true;
        state.recompute();

        assert_eq!(state.selected_ip, "");
        assert_eq!(state.amp_ip, "", "an explicit clear must NOT fall back to auto-select, even with exactly one known amp");
        assert_eq!(state.device_name, "");
        assert!(!state.online);
    }

    #[test]
    fn never_explicitly_selected_still_auto_selects_the_sole_known_amp() {
        // Companion to the test above: auto-select-if-alone must still
        // apply when nothing has ever been chosen (a fresh start with
        // nothing persisted).
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        state.selected_ip = "192.168.1.50".to_string();
        state.has_explicit_selection = true;
        state.recompute();

        // A fresh "never chosen" AmpState seeing one amp, independent of
        // the state above.
        let mut fresh_state = AmpState::default();
        fresh_state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));

        assert_eq!(fresh_state.selected_ip, "");
        assert!(!fresh_state.has_explicit_selection);
        assert_eq!(fresh_state.amp_ip, "192.168.1.50", "auto-select-if-alone must still work when nothing was ever explicitly chosen");
        assert_eq!(fresh_state.device_name, "Living Room Amp");
    }

    #[test]
    fn known_amps_is_sorted_by_ip_for_a_stable_emission_order() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.99".to_string(), parsed_status("Z Amp"));
        state.ingest_status("192.168.1.10".to_string(), parsed_status("A Amp"));

        let ips: Vec<&str> = state.known_amps.iter().map(|(ip, _, _, _)| ip.as_str()).collect();
        assert_eq!(ips, vec!["192.168.1.10", "192.168.1.99"]);
    }

    /// `.9` vs `.10` distinguishes numeric from lexicographic sorting; the
    /// test above agrees under both.
    #[test]
    fn known_amps_sorts_numerically_not_lexicographically() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.10".to_string(), parsed_status("Ten"));
        state.ingest_status("192.168.1.9".to_string(), parsed_status("Nine"));

        let ips: Vec<&str> = state.known_amps.iter().map(|(ip, _, _, _)| ip.as_str()).collect();
        // Lexicographically "192.168.1.10" < "192.168.1.9" (the '1' after
        // the shared "192.168.1." prefix sorts before '9'), which is the
        // wrong order for what a human expects from "sorted by IP".
        assert_eq!(ips, vec!["192.168.1.9", "192.168.1.10"]);
    }

    #[test]
    fn resolving_a_known_amp_updates_known_amps_and_becomes_the_primary_device_name() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("My Devialet-ETH"));

        let applied = state.resolve_model_name("192.168.1.50", "Devialet Expert 140 Pro".to_string());

        assert!(applied);
        assert_eq!(
            state.known_amps.iter().find(|(ip, ..)| ip == "192.168.1.50").unwrap().3,
            "Devialet Expert 140 Pro"
        );
        // modelName ?: udpName - the primary DeviceName property prefers
        // the resolved model name over the raw UDP broadcast name.
        assert_eq!(state.device_name, "Devialet Expert 140 Pro");
    }

    #[test]
    fn resolving_an_ip_never_heard_over_udp_is_rejected() {
        // _spotify-connect._tcp isn't Devialet-specific - a resolution for
        // an IP this daemon never saw a real UDP broadcast from must be
        // discarded, not trusted as if it were a known amp.
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("My Devialet-ETH"));

        let applied = state.resolve_model_name("192.168.1.77", "Some Other Spotify Speaker".to_string());

        assert!(!applied);
        assert_eq!(state.known_amps.len(), 1, "no new entry should be created for an unknown IP");
        assert!(state.known_amps.iter().all(|(_, _, _, model)| model.is_empty()));
    }

    #[test]
    fn unresolved_model_name_falls_back_to_raw_udp_device_name() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("My Devialet-ETH"));

        // No resolve_model_name call at all - mirrors "resolution hasn't
        // completed yet, or never succeeds" (e.g. no mDNS on the network).
        assert_eq!(state.device_name, "My Devialet-ETH");
        assert_eq!(state.known_amps[0].3, "", "unresolved model name is empty, not absent/blank-but-set");
    }

    // ---- persisted-selection startup behaviour ----
    //
    // `set_persisted_selection` is what `main()` calls once at startup with
    // the result of `config::load_selected_ip()`.

    #[test]
    fn persisted_real_ip_is_restored_but_not_connected_until_a_real_broadcast_arrives() {
        // A persisted IP is reported in `AmpIp`/`SelectedAmpIp` at once,
        // but not `Online` until a broadcast from it is ingested.
        let mut state = AmpState::default();
        state.set_persisted_selection("192.168.1.50".to_string());

        assert_eq!(state.selected_ip, "192.168.1.50");
        assert_eq!(state.amp_ip, "192.168.1.50", "the persisted IP should still be reported, just not yet connected");
        assert!(!state.online, "must not be treated as connected before a real broadcast is heard");
        assert_eq!(state.device_name, "");

        // Now the amp actually broadcasts - reconciliation completes.
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        assert!(state.online, "must reconnect once a real broadcast from the persisted IP arrives");
        assert_eq!(state.device_name, "Living Room Amp");
    }

    #[test]
    fn switching_persisted_selection_to_a_different_amp_shows_the_new_one_not_the_old() {
        // A fresh AmpState loading B's IP reflects B once it broadcasts,
        // with no trace of A.
        let mut state = AmpState::default();
        state.set_persisted_selection("192.168.1.51".to_string());
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Amp A"));
        state.ingest_status("192.168.1.51".to_string(), parsed_status("Amp B"));

        assert_eq!(state.amp_ip, "192.168.1.51");
        assert_eq!(state.device_name, "Amp B");
        assert!(state.online);
    }

    #[test]
    fn persisted_explicit_none_does_not_resurrect_auto_select_after_a_broadcast_arrives() {
        // A persisted "" must set has_explicit_selection, not just
        // selected_ip="", or auto-select-if-alone resurrects a selection
        // through startup loading.
        let mut state = AmpState::default();
        state.set_persisted_selection(String::new());

        assert_eq!(state.selected_ip, "");
        assert!(state.has_explicit_selection, "a persisted \"\" must count as an explicit selection, not the default");
        assert_eq!(state.amp_ip, "");
        assert!(!state.online);

        // The one amp on the network broadcasts - with a genuine "never
        // selected" state this would auto-select it (see
        // never_explicitly_selected_still_auto_selects_the_sole_known_amp
        // above); with a persisted explicit None it must NOT.
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));

        assert_eq!(state.amp_ip, "", "a persisted explicit None must stay None even once an amp is heard from");
        assert_eq!(state.device_name, "");
        assert!(!state.online);
    }

    #[test]
    fn persisted_ip_for_an_amp_that_never_reappears_stays_not_connected() {
        // A persisted IP for an amp gone from the network stays not
        // connected, whatever other amps broadcast.
        let mut state = AmpState::default();
        state.set_persisted_selection("192.168.1.50".to_string());
        state.ingest_status("192.168.1.99".to_string(), parsed_status("Some Other Amp"));

        assert_eq!(state.amp_ip, "192.168.1.50", "the explicit selection must not be displaced by an unrelated amp broadcasting");
        assert!(!state.online);
        assert_eq!(state.device_name, "");
    }

    // `select_amp` itself is not unit-tested here (async zbus method, no
    // interface context); config.rs tests the save/load round trip.

    #[test]
    fn resolved_model_name_survives_a_later_udp_broadcast_from_the_same_amp() {
        // Re-ingestion must carry the resolved name forward, not wipe it
        // on every broadcast.
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("My Devialet-ETH"));
        state.resolve_model_name("192.168.1.50", "Devialet Expert 140 Pro".to_string());

        // A later UDP broadcast from the same amp (e.g. next ~1s status
        // packet) must not wipe the already-resolved model name.
        state.ingest_status("192.168.1.50".to_string(), parsed_status("My Devialet-ETH"));

        assert_eq!(state.device_name, "Devialet Expert 140 Pro");
        assert_eq!(state.known_amps[0].3, "Devialet Expert 140 Pro");
    }

    // ---- three-state PowerState (Off/Booting/On) ----
    //
    // `begin_power_on_boot` is async (no zbus context here), so these tests
    // set `boot_deadline` directly, as the method would, to cover
    // `resolve_boot_deadlines`/`recompute`. Its already-booting guard is
    // not covered here.

    #[test]
    fn power_state_is_off_when_never_booting_and_amp_reports_off() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status_off("Living Room Amp"));

        assert_eq!(state.power_state, "Off");
        assert!(!state.power);
    }

    #[test]
    fn power_state_is_booting_while_a_deadline_is_pending_even_though_power_is_still_false() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status_off("Living Room Amp"));

        state.amps.get_mut("192.168.1.50").unwrap().boot_deadline = Some(Instant::now() + Duration::from_secs(15));
        state.recompute();

        assert_eq!(state.power_state, "Booting");
        // `Power` stays a pure, unfiltered reflection of the amp's real
        // UDP status - it must NOT flip true just because a boot started.
        assert!(!state.power);
    }

    #[test]
    fn power_state_resolves_to_on_once_a_real_broadcast_confirms_power_and_clears_the_deadline() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status_off("Living Room Amp"));
        state.amps.get_mut("192.168.1.50").unwrap().boot_deadline = Some(Instant::now() + Duration::from_secs(15));
        state.recompute();
        assert_eq!(state.power_state, "Booting");

        // The real amp broadcasts power_on = true before the deadline -
        // ingest_status carries the still-pending deadline forward (see
        // its own doc), and recompute must resolve it to "On" and clear it.
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));

        assert_eq!(state.power_state, "On");
        assert!(state.power);
        assert!(
            state.amps.get("192.168.1.50").unwrap().boot_deadline.is_none(),
            "a resolved boot must not leave a stale deadline behind"
        );
    }

    #[test]
    fn power_state_falls_back_to_off_once_the_deadline_elapses_with_no_confirmation() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status_off("Living Room Amp"));

        // Deadline already in the past: BOOT_TIMEOUT elapsed with no "on"
        // broadcast (a failed boot).
        state.amps.get_mut("192.168.1.50").unwrap().boot_deadline = Some(Instant::now() - Duration::from_millis(1));
        state.recompute();

        assert_eq!(state.power_state, "Off", "silent fallback, no distinct error state");
        assert!(!state.power);
        assert!(
            state.amps.get("192.168.1.50").unwrap().boot_deadline.is_none(),
            "an expired deadline must be cleared, not left pending forever"
        );
    }

    #[test]
    fn a_non_primary_amps_boot_still_resolves_even_though_nothing_reads_it_yet() {
        // resolve_boot_deadlines clears a non-primary amp's deadline too.
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Primary Amp"));
        state.selected_ip = "192.168.1.50".to_string();
        state.has_explicit_selection = true;
        state.ingest_status("192.168.1.51".to_string(), parsed_status_off("Other Amp"));
        state.amps.get_mut("192.168.1.51").unwrap().boot_deadline = Some(Instant::now() - Duration::from_millis(1));

        state.recompute();

        assert_eq!(state.power_state, "On", "primary amp (.50) is unaffected by the other amp's boot");
        assert!(
            state.amps.get("192.168.1.51").unwrap().boot_deadline.is_none(),
            "the non-primary amp's expired deadline must still be cleared"
        );
    }

    // ---- boot of a selected amp not heard since daemon start
    // (persisted selection, amp unreachable) ----

    #[test]
    fn a_boot_of_a_selected_but_never_heard_amp_reports_booting_then_times_out_to_off() {
        let mut state = AmpState::default();
        state.set_persisted_selection("192.168.1.50".to_string());
        assert_eq!(state.power_state, "Off");

        assert!(state.begin_unheard_boot("192.168.1.50".to_string()));
        state.recompute();
        assert_eq!(state.power_state, "Booting");
        assert!(!state.power);

        // A repeated call must not extend the deadline.
        let deadline = state.unheard_boot_deadlines["192.168.1.50"];
        assert!(!state.begin_unheard_boot("192.168.1.50".to_string()));
        assert_eq!(state.unheard_boot_deadlines["192.168.1.50"], deadline);

        // BOOT_TIMEOUT elapsed with the amp still silent.
        state.unheard_boot_deadlines.insert("192.168.1.50".to_string(), Instant::now() - Duration::from_millis(1));
        state.recompute_staleness();
        assert_eq!(state.power_state, "Off", "the widget's Booting state must end");
        assert!(state.unheard_boot_deadlines.is_empty(), "an expired deadline must be dropped");
    }

    #[test]
    fn an_unheard_boot_deadline_moves_onto_the_amp_when_its_first_broadcast_arrives() {
        let mut state = AmpState::default();
        state.set_persisted_selection("192.168.1.50".to_string());
        assert!(state.begin_unheard_boot("192.168.1.50".to_string()));

        // First broadcast still reports off (mid-boot): stays Booting.
        state.ingest_status("192.168.1.50".to_string(), parsed_status_off("Living Room Amp"));
        assert_eq!(state.power_state, "Booting");
        assert!(state.unheard_boot_deadlines.is_empty());
        assert!(state.amps.get("192.168.1.50").unwrap().boot_deadline.is_some());

        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        assert_eq!(state.power_state, "On");
        assert!(state.amps.get("192.168.1.50").unwrap().boot_deadline.is_none());
    }

    #[test]
    fn an_unheard_boot_of_a_non_selected_ip_does_not_touch_the_primary_power_state() {
        let mut state = AmpState::default();
        state.set_persisted_selection("192.168.1.50".to_string());
        assert!(state.begin_unheard_boot("192.168.1.99".to_string()));
        state.recompute();
        assert_eq!(state.power_state, "Off");
    }

    // ---- daemon-owned pending-command state (VolumeDb/Muted) ----
    //
    // `notify_volume_command`/`notify_mute_command` are async (no zbus
    // context here), so these tests set `pending_volume_db`/`pending_muted`
    // directly to cover `resolve_pending_commands`/`recompute`. The
    // methods' unknown-ip guard and the `VolumeCommandNotified`/
    // `MuteCommandNotified` signals are not covered here; the signals need
    // a live `SignalEmitter` (check with `busctl monitor`).

    #[test]
    fn pending_volume_is_reported_instead_of_the_amps_last_real_value_while_live() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        assert_eq!(state.volume_db, 0.0, "fixture's real volume_raw=195 decodes to 0.0dB");

        state.amps.get_mut("192.168.1.50").unwrap().pending_volume_db = Some((-24.0, Instant::now() + Duration::from_millis(400)));
        state.recompute();

        assert_eq!(state.volume_db, -24.0, "a live pending value must override the amp's last real status");
    }

    #[test]
    fn pending_muted_is_reported_instead_of_the_amps_last_real_value_while_live() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp"));
        assert!(!state.muted, "fixture's real status.muted defaults to false");

        state.amps.get_mut("192.168.1.50").unwrap().pending_muted = Some((true, Instant::now() + Duration::from_millis(400)));
        state.recompute();

        assert!(state.muted, "a live pending value must override the amp's last real status");
    }

    #[test]
    fn pending_volume_clears_once_a_real_broadcast_confirms_it() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp")); // volume_raw 195 -> 0.0dB
        state.amps.get_mut("192.168.1.50").unwrap().pending_volume_db = Some((-24.0, Instant::now() + Duration::from_secs(10)));
        state.recompute();
        assert_eq!(state.volume_db, -24.0, "pending value should show before any confirmation arrives");

        // Amp confirms: volume_raw=147 decodes to (147-195)/2 = -24.0, an
        // exact match (see resolve_pending_commands).
        let confirming = StatusFixtureBuilder::new()
            .device_name("Living Room Amp")
            .source(0, "Optical 1", true)
            .active_source_index(0)
            .power(true)
            .volume_raw(147)
            .build();
        state.ingest_status("192.168.1.50".to_string(), proto::parse_status(&confirming).unwrap());

        assert_eq!(state.volume_db, -24.0, "the now-real value should still read -24.0");
        assert!(
            state.amps.get("192.168.1.50").unwrap().pending_volume_db.is_none(),
            "a confirmed pending command must be cleared, not left dangling"
        );
    }

    #[test]
    fn pending_muted_clears_once_a_real_broadcast_confirms_it() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp")); // muted=false
        state.amps.get_mut("192.168.1.50").unwrap().pending_muted = Some((true, Instant::now() + Duration::from_secs(10)));
        state.recompute();
        assert!(state.muted, "pending value should show before any confirmation arrives");

        let confirming = StatusFixtureBuilder::new()
            .device_name("Living Room Amp")
            .source(0, "Optical 1", true)
            .active_source_index(0)
            .power(true)
            .muted(true)
            .volume_raw(195)
            .build();
        state.ingest_status("192.168.1.50".to_string(), proto::parse_status(&confirming).unwrap());

        assert!(state.muted, "the now-real value should still read true");
        assert!(
            state.amps.get("192.168.1.50").unwrap().pending_muted.is_none(),
            "a confirmed pending command must be cleared, not left dangling"
        );
    }

    #[test]
    fn pending_volume_falls_back_to_the_real_value_once_the_deadline_elapses_with_no_confirmation() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp")); // real 0.0dB
        state.amps.get_mut("192.168.1.50").unwrap().pending_volume_db = Some((-24.0, Instant::now() - Duration::from_millis(1)));
        state.recompute();

        assert_eq!(state.volume_db, 0.0, "an expired pending value must fall back to the amp's real last-known value");
        assert!(
            state.amps.get("192.168.1.50").unwrap().pending_volume_db.is_none(),
            "an expired deadline must be cleared, not left pending forever"
        );
    }

    #[test]
    fn pending_muted_falls_back_to_the_real_value_once_the_deadline_elapses_with_no_confirmation() {
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp")); // real false
        state.amps.get_mut("192.168.1.50").unwrap().pending_muted = Some((true, Instant::now() - Duration::from_millis(1)));
        state.recompute();

        assert!(!state.muted, "an expired pending value must fall back to the amp's real last-known value");
        assert!(
            state.amps.get("192.168.1.50").unwrap().pending_muted.is_none(),
            "an expired deadline must be cleared, not left pending forever"
        );
    }

    #[test]
    fn a_second_pending_volume_command_replaces_the_first_and_resets_the_deadline() {
        // A rapid scroll: NotifyVolumeCommand always overwrites, so the
        // latest command and its own fresh deadline must govern.
        let mut state = AmpState::default();
        state.ingest_status("192.168.1.50".to_string(), parsed_status("Living Room Amp")); // real 0.0dB

        // First command's deadline is already in the past - if a second
        // command didn't fully replace this (value AND deadline), the very
        // next recompute() would fall back to the real value instead of
        // reporting the second command's.
        state.amps.get_mut("192.168.1.50").unwrap().pending_volume_db = Some((-24.0, Instant::now() - Duration::from_millis(1)));

        // A second command (e.g. the next notch of a fast scroll) arrives
        // before that expired state is ever resolved by a recompute() call.
        state.amps.get_mut("192.168.1.50").unwrap().pending_volume_db = Some((-22.0, Instant::now() + Duration::from_secs(10)));
        state.recompute();

        assert_eq!(
            state.volume_db, -22.0,
            "the latest command must win outright, not fall back just because an earlier one's original deadline had passed"
        );
        assert!(
            state.amps.get("192.168.1.50").unwrap().pending_volume_db.is_some(),
            "the second command's own fresh deadline must be what's now in effect, not the first (already-expired) one"
        );
    }
}
