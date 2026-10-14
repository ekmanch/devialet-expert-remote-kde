// The flyout content root, hosted in FlyoutPopup.qml's mainItem. Holds
// the flyout's amp state and command surface and lays out the rows:
// AmpHeader, VolumeBlock, ActionRow, SourceSelector, Footer, plus the
// two overlay Popups (AmpListOverlay, SourceListOverlay).
//
// State ownership:
// - Volume and mute are not mirrored here: they are read from
//   `pendingAmpState`, the shared daemon-resolved state (docs/DESIGN.md
//   §3), and written through its notifyVolume()/notifyMute().
// - Power/PowerState and ActiveSourceIndex/ActiveSourceName are mirrored
//   here from D-Bus. The daemon has no pending-command state for them, so
//   each pair has its own 400 ms guard against the late broadcast after
//   an optimistic local write (`lastPowerChangeAtMs`,
//   `lastSourceChangeAtMs`, applied in onPropertiesChanged).
// - Sources and KnownAmps are arrays of structs whose PropertiesChanged
//   payload is not trustworthy on repeat updates, so a change triggers an
//   explicit Get instead (fetchSourcesFresh()/fetchKnownAmpsFresh()).
// - The configured startup volume is sent with every source switch
//   (selectSource()) and after a widget-initiated power-on (documented at
//   `pendingStartupVolumeIp`).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as Dbus
import org.kde.plasma.plasma5support as P5Support

Item {
    id: root

    required property PlasmoidItem plasmoidItem
    // Shared, daemon-resolved volume/mute state (see header).
    required property PendingAmpState pendingAmpState
    // Shared volume-range config (floor/hard-limit/step/startup dB).
    required property VolumeSettings volumeSettings
    // Shared transparency alpha; drives the tint gradient below.
    required property TransparencySettings transparencySettings
    // Bound one-way from FlyoutPopup.visible; drives the overlay reset on
    // flyout hide below.
    property bool popupVisible: false

    readonly property Theme theme: Theme {}
    // The theme, resolved by ThemeSettings; `colors` is the flyout's
    // palette, forwarded to every child alongside `theme`.
    required property ThemeSettings themeSettings
    readonly property ColorPalette colors: root.themeSettings.flyoutPalette

    implicitWidth: theme.panelWidth
    implicitHeight: mainColumn.implicitHeight

    // ---- amp state (header subset) ----
    property bool online: false
    property string deviceName: ""
    property string ampIp: ""
    property bool power: false
    property string powerState: "Off"
    property var knownAmps: []
    property string selectedAmpIp: ""

    // ---- source state ----
    // ActiveSourceName/ActiveSourceIndex are scalars (`s`, `y`) and are
    // read straight from PropertiesChanged, behind the source guard.
    // `sources` (a(sybb)) is array-of-struct, so it is re-fetched (see
    // fetchSourcesFresh()).
    property string activeSourceName: ""
    property int activeSourceIndex: -1
    property var sources: []
    property double lastSourceChangeAtMs: 0

    property bool sourcesFetchInFlight: false

    function unwrapSources(raw) {
        if (raw === undefined || raw === null) return [];
        var result = [];
        for (var i = 0; i < raw.length; i++) {
            var t = raw[i];
            result.push({
                name: root.unwrap(t[0], ""),
                index: root.unwrap(t[1], i),
                enabled: t[2],
                selected: t[3]
            });
        }
        return result;
    }

    // Sources' PropertiesChanged payload is not trustworthy on repeat
    // updates, so re-fetch with an explicit Get on the signal rather than
    // trusting `changed.Sources` (same as fetchKnownAmpsFresh()).
    function fetchSourcesFresh() {
        if (root.sourcesFetchInFlight) return;
        root.sourcesFetchInFlight = true;
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: "com.ekmanch.DevialetRemote",
                path: "/com/ekmanch/DevialetRemote/Amp",
                interface: "org.freedesktop.DBus.Properties",
                member: "Get",
                arguments: ["com.ekmanch.DevialetRemote.Amp1", "Sources"]
            }),
            function (reply) {
                root.sourcesFetchInFlight = false;
                if (reply.isError) {
                    console.log("[WARN] explicit Get(Sources) returned a D-Bus error:", JSON.stringify(reply.error));
                    return;
                }
                const unwrapped = root.unwrapSources(root.unwrap(reply.value, []));
                if (unwrapped.length > 0) {
                    root.sources = unwrapped;
                } else {
                    console.log("[WARN] explicit Get(Sources) resolved but produced no usable data:", JSON.stringify(reply.value).substring(0, 200));
                }
            },
            function (reply) {
                root.sourcesFetchInFlight = false;
                console.log("[WARN] explicit Get(Sources) call failed:", JSON.stringify(reply.error));
            }
        );
    }

    // Called from SourceListOverlay's sourceChosen signal. index/name are
    // already validated against the overlay's own model (its onClicked),
    // so no bounds check here.
    function selectSource(index, name) {
        // Power gate (gotcha #10): the row is already inert unless "On"
        // (SourceSelector.interactive); repeated for the overlay's own
        // click path.
        if (root.ampIp === "" || root.powerState !== "On") return;
        root.activeSourceIndex = index;
        root.activeSourceName = name;
        root.lastSourceChangeAtMs = root.now();
        // Every source switch sends the configured startup volume
        // (gotcha #5). Pre-clamped to [floor, hardLimit] like every other
        // volume-set path, since nothing downstream re-applies the floor;
        // the CLI clamps to the hard limit again itself. Sent in the same
        // invocation as the switch: the amp honoured the zero-delay
        // source+volume pair 6/6. notifyVolume() makes the flyout, OSD and
        // tooltip show the post-switch volume at once.
        const target = root.volumeSettings.clamp(root.volumeSettings.startupVolumeDb);
        root.runCtl("source " + index + " --hard-limit-db " + root.volumeSettings.hardLimitDb
                    + " --startup-volume-db " + target);
        root.pendingAmpState.notifyVolume(target);
    }

    readonly property string devialetCtlCommand: "devialet-ctl"

    // ---- volume chime ----
    // One gain-compensated chime per discrete step, only while the PC is
    // the amp's source (Optical 1 - the PC -> HDMI -> TV -> optical path).
    // The binary does the math; QML supplies the two dB values it already
    // holds: the optimistic target (the OSD's own number) and the amp's
    // real last-broadcast dB (pendingAmpState.confirmedVolumeDb, decoded
    // from the daemon's unmasked VolumeRaw).
    readonly property string chimeCommand: "devialet-chime"
    // Round-robin pool of DataSources, not one reused id:
    // KDE's Audio Devices tone plays via libcanberra, which spawns a fresh
    // stream per trigger so rapid triggers overlap and mix instead of
    // interrupting each other. Tick N uses chimePool[N % length]. Four
    // slots: the chime is 0.30 s and even ~10 ticks/s leaves at most 3 in
    // flight. The `--tick` argument keeps concurrently running chimes'
    // command strings distinct - Plasma's executable engine is shared
    // process-wide and keys running jobs by command string, so two ticks
    // with identical dB arguments would otherwise collapse into one
    // process regardless of the pool. The set of strings must stay
    // bounded, though: see VolumeSettings.chimeArguments() and
    // docs/DESIGN.md §5.
    readonly property var chimePool: [chimeExec0, chimeExec1, chimeExec2, chimeExec3]
    property int chimeTick: 0

    // Gate on the amp's live broadcast name, trimmed + lowercased (the
    // SourceGlyph.kindFor() keyword-match precedent; never by index - see
    // crates/protocol command.rs). Any other source: no chime at all.
    function isPcSourceActive() {
        return String(root.activeSourceName || "").trim().toLowerCase() === "optical 1";
    }

    function maybeChime(targetDb) {
        // The settings' master toggle (main.xml chimeEnabled, via
        // VolumeSettings). Checked first so an off toggle spawns no
        // devialet-chime process at all.
        if (!root.volumeSettings.chimeEnabled) return;
        if (!root.isPcSourceActive()) return;
        const confirmed = root.pendingAmpState.confirmedVolumeDb;
        if (typeof confirmed !== "number" || typeof targetDb !== "number") return;
        // The chime source (VolumeSettings.chimeFileArgument()): "" in
        // follow mode (no --file); " --file '<path>'" for a pinned theme or
        // a picked file; null when the mode needs a file but none resolves:
        // skip and warn, never silently fall back to another mode.
        const fileArg = root.volumeSettings.chimeFileArgument();
        if (fileArg === null) {
            console.warn("devialet-chime: source mode", root.volumeSettings.chimeSourceMode, "has no resolvable file - skipping");
            return;
        }
        const slot = root.chimeTick % root.chimePool.length;
        // The binary reads target/confirmed from the daemon itself (one
        // GetAll, see crates/devialet-chime/src/daemon.rs), so the command
        // is only `--tick k` - a fixed set of strings. QML's own values are
        // logged as the reference for the notch-vs-read timing comparison.
        const cmd = root.chimeCommand + root.volumeSettings.chimeArguments(root.chimeTick) + fileArg;
        root.chimeTick += 1;
        console.log("devialet-chime[" + slot + "] running:", cmd, "(qml target=" + targetDb.toFixed(1) + " confirmed=" + confirmed.toFixed(1) + ")");
        root.chimePool[slot].connectSource(cmd);
    }

    // ---- action row (mute/power) state ----
    // Guard window for the Power/PowerState and source mirrors (see
    // header): the daemon has no pending-command state for them.
    readonly property int debounceMs: 400
    property double lastPowerChangeAtMs: 0

    function now() { return Date.now(); }
    function within(lastMs, windowMs) { return (root.now() - lastMs) < windowMs; }

    function runCtl(argsString) {
        const cmd = root.devialetCtlCommand + " --ip " + root.ampIp + " " + argsString;
        console.log("running:", cmd);
        exec.connectSource(cmd);
    }

    // Button/wheel step, mirroring CompactRepresentation.qml's
    // stepVolume(). Reads pendingAmpState.volumeDb as its base: safe
    // because notifyVolume() writes it synchronously before its D-Bus
    // call, so a rapid second step reads the value this call just set.
    function stepVolume(direction) {
        // Power gate (gotcha #10): VolumeBlock already disables its inputs
        // unless "On" (its `interactive`); this repeats the check for
        // autoRepeat ticks already queued when the state flips.
        if (root.ampIp === "" || root.powerState !== "On") return;
        const clamped = root.volumeSettings.stepped(root.pendingAmpState.volumeDb, direction);
        // A volume change from any input (panel scroll, the flyout's
        // +/- buttons or slider) unmutes for real, matching KDE's Audio
        // Devices applet. Applied consistently on every volume input.
        if (root.pendingAmpState.muted) {
            root.runCtl("mute off");
            root.pendingAmpState.notifyMute(false);
        }
        root.runCtl("volume " + clamped + " --hard-limit-db " + root.volumeSettings.hardLimitDb);
        root.pendingAmpState.notifyVolume(clamped);
        // One attempted chime per discrete step, no debounce. Reached by
        // the slider's wheel notches and the +/- buttons (both emit
        // VolumeBlock.stepRequested); releaseVolume() deliberately does
        // not chime.
        root.maybeChime(clamped);
    }

    // Slider release. The drag result is already bounded by the Slider's
    // from/to, but still goes through the shared clamp() so no sent value
    // depends on the Slider's bounds being right.
    function releaseVolume(value) {
        if (root.ampIp === "" || root.powerState !== "On") return;
        const clamped = root.volumeSettings.clamp(value);
        // Same unmute-on-volume-change as stepVolume().
        if (root.pendingAmpState.muted) {
            root.runCtl("mute off");
            root.pendingAmpState.notifyMute(false);
        }
        root.runCtl("volume " + clamped + " --hard-limit-db " + root.volumeSettings.hardLimitDb);
        root.pendingAmpState.notifyVolume(clamped);
    }

    // Mirrors CompactRepresentation.qml's toggleMute(): reads
    // pendingAmpState.muted directly, no local mirror, no guard.
    function toggleMute() {
        // Power gate (gotcha #10), see ActionRow.muteInteractive.
        if (root.ampIp === "" || root.powerState !== "On") return;
        const newMuted = !root.pendingAmpState.muted;
        root.runCtl("mute " + (newMuted ? "on" : "off"));
        root.pendingAmpState.notifyMute(newMuted);
    }

    // Tells the daemon a power-on boot is starting, so it tracks
    // BOOT_TIMEOUT. togglePower() calls it right before runCtl("power on")
    // in the same handler, both fire-and-forget, so the power-on command
    // never goes out before the daemon knows a boot is in progress.
    function beginPowerOnBoot() {
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: "com.ekmanch.DevialetRemote",
                path: "/com/ekmanch/DevialetRemote/Amp",
                interface: "com.ekmanch.DevialetRemote.Amp1",
                member: "BeginPowerOnBoot",
                arguments: [root.ampIp]
            }),
            function (reply) {
                if (reply.isError) {
                    console.log("[WARN] BeginPowerOnBoot call returned a D-Bus error:", JSON.stringify(reply.error));
                }
            },
            function (reply) {
                console.log("[WARN] BeginPowerOnBoot call failed:", JSON.stringify(reply.error));
            }
        );
    }

    // Optimistic set on both power/powerState, stamped so the guard in
    // onPropertiesChanged holds them through the 400 ms window.
    function togglePower() {
        if (root.ampIp === "" || root.powerState === "Booting") return;
        const newPower = !root.power;
        root.power = newPower;
        root.powerState = newPower ? "Booting" : "Off";
        root.lastPowerChangeAtMs = root.now();
        // Arm (or, on a power-off click, disarm) the post-boot startup
        // volume - see the block after this function.
        // After the optimistic assignments: the "Booting" they trigger in
        // onPowerStateChanged is a no-op there anyway.
        if (newPower) {
            root.pendingStartupVolumeIp = root.ampIp;
        } else {
            root.pendingStartupVolumeIp = "";
            startupVolumeTimer.stop();
            root.pendingAmpState.endBootHold();
        }
        if (newPower) {
            // Tell the daemon first, then send the command (see
            // beginPowerOnBoot()). Power-off is immediate, no daemon
            // notification.
            root.beginPowerOnBoot();
        }
        root.runCtl("power " + (newPower ? "on" : "off"));
    }

    // ---- startup volume after a widget-initiated power-on ----
    // Widget-initiated power-on only; an external power-on (remote, front
    // panel) is not covered. The daemon's PowerState is the boot
    // confirmation, observed here because this file owns the only
    // PowerState mirror and the only `power on` call site. Power-on and
    // the volume cannot share one devialet-ctl invocation (the CLI cannot
    // wait out a 15-19 s boot), so the volume is a separate send once "On"
    // is observed.
    //
    // Why 500 ms after "On" and not 0: a volume command that reaches the
    // amp before its own post-boot startup-volume application is dropped
    // (gotcha #9). That application lands anywhere from before the first
    // "On" to just over +400 ms after it; 500 is the smallest round value
    // above the latest observed, passed every trial, and is imperceptible
    // after a 15 s boot.
    //
    // State: the IP captured at click time ("" = not armed), so a switch
    // to another amp mid-boot cannot fire at the wrong amp. It lives here
    // because FlyoutPopup is a plain Dialog child of CompactRepresentation
    // with no Loader, so this item stays resident while the flyout is
    // hidden during the boot.
    //
    // Ordering: onPowerStateChanged fires synchronously inside
    // ampProps.onPropertiesChanged, after AmpIp has been assigned; nothing
    // here reads pendingAmpState.volumeDb, and the Timer defers the send
    // past the whole handler anyway. Every armed state resolves: the
    // daemon ends Booting with On or Off within BOOT_TIMEOUT, bootWatchdog
    // ends it when the daemon stays silent, and "Off" disarms.
    //
    // Display: on "On" the hold in PendingAmpState.qml is armed with the
    // target, so no surface shows the amp's pre-shutdown or misreported
    // post-boot value (gotcha #8) before the send lands. The send reads
    // the hold's current target, so a user volume change inside that
    // window wins on the amp too (docs/DESIGN.md §3).
    property string pendingStartupVolumeIp: ""
    readonly property int startupVolumeAfterBootMs: 500

    Timer {
        id: startupVolumeTimer
        interval: root.startupVolumeAfterBootMs
        repeat: false
        onTriggered: root.sendStartupVolume()
    }

    // Bounds "Booting" when the daemon never ends it - see
    // BootWatchdog.qml. Assigning "Off" here runs onPowerStateChanged's
    // "Off" branch below, which also disarms the startup volume.
    // daemonPowerState is the unguarded copy of the daemon's PowerState
    // (the mirror above skips pushes inside the 400 ms click guard).
    property string daemonPowerState: "Off"
    readonly property BootWatchdog bootWatchdog: BootWatchdog {
        powerState: root.powerState
        daemonPowerState: root.daemonPowerState
        onExpired: (fallbackState, reason) => {
            console.log("[WARN] ending Booting ->", fallbackState, "-", reason);
            root.power = fallbackState === "On";
            root.powerState = fallbackState;
        }
    }

    onPowerStateChanged: {
        // A source list left open when the amp goes off/booting closes;
        // its row is no longer interactive.
        if (root.powerState !== "On") root.sourceListOpen = false;
        if (root.pendingStartupVolumeIp === "") return;
        if (root.powerState === "On") {
            if (root.ampIp !== root.pendingStartupVolumeIp) {
                // The selected amp changed mid-boot - this "On" is not the
                // amp we powered on. Disarm; never fire at the wrong amp.
                root.pendingStartupVolumeIp = "";
                startupVolumeTimer.stop();
                return;
            }
            root.pendingAmpState.beginBootHold(root.pendingStartupVolumeIp, root.startupVolumeTarget());
            startupVolumeTimer.restart();
        } else if (root.powerState === "Off") {
            root.pendingStartupVolumeIp = "";
            startupVolumeTimer.stop();
            root.pendingAmpState.endBootHold();
        }
        // "Booting": nothing to do yet.
    }

    // Configured startup volume, pre-clamped to [floor, hardLimit] - see
    // selectSource() for why both ends are applied here.
    function startupVolumeTarget() {
        return root.volumeSettings.clamp(root.volumeSettings.startupVolumeDb);
    }

    function sendStartupVolume() {
        const ip = root.pendingStartupVolumeIp;
        root.pendingStartupVolumeIp = "";
        if (ip === "" || ip !== root.ampIp) return;
        // Latest intended value: the hold's target if a user change inside
        // the window re-targeted it, else the configured startup volume.
        const held = root.pendingAmpState.bootHoldIp !== "";
        const target = held ? root.pendingAmpState.bootHoldDb : root.startupVolumeTarget();
        // No `mute off` here: volume and mute are independent opcodes,
        // and a startup volume is not a user's volume gesture.
        root.runCtl("volume " + target + " --hard-limit-db " + root.volumeSettings.hardLimitDb);
        root.pendingAmpState.notifyVolume(target);
    }

    // Fires devialet-ctl once per connectSource() call, then disconnects
    // itself - same pattern as CompactRepresentation.qml's `exec`.
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-ctl finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    // The four-slot round-robin pool maybeChime() cycles through - see
    // the chimePool comment above. Same shape as `exec`,
    // distinct log prefix so the journal trail can be grepped per slot.
    P5Support.DataSource {
        id: chimeExec0
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[0] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: chimeExec1
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[1] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: chimeExec2
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[2] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: chimeExec3
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            console.log("devialet-chime[3] finished - exit code:", data["exit code"], "stderr:", data["stderr"]);
            disconnectSource(source);
        }
    }

    // The UI-state hooks (harness `uiTarget` points here), one per
    // overlay Popup (docs/DESIGN.md §3). Writers are all imperative; no
    // binding touches them, so the trigger->overlay->Popup chains can't
    // loop.
    property bool ampListOpen: false
    property bool sourceListOpen: false
    // Harness-only: a UiState key pinning the theme for a
    // capture ("dark"/"light"; "" = follow the setting). Pushed into
    // ThemeSettings.harnessOverride; the harness sends "" on teardown.
    property string themeOverride: ""
    onThemeOverrideChanged: {
        console.log("[FlyoutContent] harness theme override:", JSON.stringify(root.themeOverride));
        root.themeSettings.harnessOverride = root.themeOverride;
    }

    // Reset both lists when the flyout hides, so neither is already
    // expanded on the next open (a QtQuick Popup does not reset on window
    // hide on its own).
    onPopupVisibleChanged: {
        if (!root.popupVisible) {
            root.ampListOpen = false;
            root.sourceListOpen = false;
        }
    }

    // Drive each overlay Popup imperatively off its own flag. close() on
    // an already-closed Popup is a no-op emitting nothing, so the
    // re-entrant path (overlay dismiss -> onClosed sets false -> here
    // calls close()) terminates safely. Mutual exclusion (opening one
    // closes the other, as in the mockup)
    // is enforced here explicitly rather than left to the two Popups'
    // press-outside close policies happening to fire: clearing the other
    // flag when it's already false emits nothing, so no ping-pong.
    onAmpListOpenChanged: {
        if (root.ampListOpen) root.sourceListOpen = false;
        root.ampListOpen ? ampListOverlay.open() : ampListOverlay.close();
    }
    onSourceListOpenChanged: {
        if (root.sourceListOpen) root.ampListOpen = false;
        root.sourceListOpen ? sourceListOverlay.open() : sourceListOverlay.close();
    }

    function unwrap(prop, fallback) {
        if (prop === undefined || prop === null) return fallback;
        if (typeof prop === "object" && prop.value !== undefined) return prop.value;
        return prop;
    }

    function unwrapKnownAmps(raw) {
        if (raw === undefined || raw === null) return [];
        var result = [];
        for (var i = 0; i < raw.length; i++) {
            var t = raw[i];
            result.push({
                ip: root.unwrap(t[0], ""),
                deviceName: root.unwrap(t[1], ""),
                online: t[2],
                modelName: root.unwrap(t[3], "")
            });
        }
        return result;
    }

    property bool knownAmpsFetchInFlight: false

    // KnownAmps is array-of-struct: its PropertiesChanged payload is not
    // trustworthy on repeat updates, so re-fetch via an explicit Get on
    // the signal rather than trusting `changed.KnownAmps`.
    function fetchKnownAmpsFresh() {
        if (root.knownAmpsFetchInFlight) return;
        root.knownAmpsFetchInFlight = true;
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: "com.ekmanch.DevialetRemote",
                path: "/com/ekmanch/DevialetRemote/Amp",
                interface: "org.freedesktop.DBus.Properties",
                member: "Get",
                arguments: ["com.ekmanch.DevialetRemote.Amp1", "KnownAmps"]
            }),
            function (reply) {
                root.knownAmpsFetchInFlight = false;
                if (reply.isError) {
                    console.log("[WARN] explicit Get(KnownAmps) returned a D-Bus error:", JSON.stringify(reply.error));
                    return;
                }
                const unwrapped = root.unwrapKnownAmps(root.unwrap(reply.value, []));
                if (unwrapped.length > 0) {
                    root.knownAmps = unwrapped;
                }
            },
            function (reply) {
                root.knownAmpsFetchInFlight = false;
                console.log("[WARN] explicit Get(KnownAmps) call failed:", JSON.stringify(reply.error));
            }
        );
    }

    function selectAmpByIp(ip) {
        root.ampListOpen = false;
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: "com.ekmanch.DevialetRemote",
                path: "/com/ekmanch/DevialetRemote/Amp",
                interface: "com.ekmanch.DevialetRemote.Amp1",
                member: "SelectAmp",
                arguments: [ip]
            }),
            function (reply) {
                if (reply.isError) {
                    console.log("[WARN] SelectAmp call returned a D-Bus error:", JSON.stringify(reply.error));
                }
            },
            function (reply) {
                console.log("[WARN] SelectAmp call failed:", JSON.stringify(reply.error));
            }
        );
    }

    readonly property string ampDisplayName: root.deviceName !== "" ? root.deviceName : "Devialet"
    readonly property string headerName: root.ampIp === "" ? "No Amplifier" : root.ampDisplayName
    readonly property string headerSub: root.ampIp === "" ? "Tap to connect" : (root.powerState === "Booting" ? "Booting…" : (root.ampIp + " · " + (root.online ? "Connected" : "Not responding")))

    Dbus.Properties {
        id: ampProps
        busType: Dbus.BusType.Session
        service: "com.ekmanch.DevialetRemote"
        path: "/com/ekmanch/DevialetRemote/Amp"
        iface: "com.ekmanch.DevialetRemote.Amp1"

        onRefreshed: {
            root.online = root.unwrap(properties.Online, false);
            root.deviceName = root.unwrap(properties.DeviceName, "");
            root.ampIp = root.unwrap(properties.AmpIp, "");
            root.power = root.unwrap(properties.Power, false);
            root.powerState = root.unwrap(properties.PowerState, "Off");
            root.daemonPowerState = root.powerState;
            root.activeSourceName = root.unwrap(properties.ActiveSourceName, "");
            root.activeSourceIndex = root.unwrap(properties.ActiveSourceIndex, -1);
            const initialSources = root.unwrapSources(root.unwrap(properties.Sources, []));
            if (initialSources.length > 0) {
                root.sources = initialSources;
            }
            const initialKnownAmps = root.unwrapKnownAmps(root.unwrap(properties.KnownAmps, []));
            if (initialKnownAmps.length > 0) {
                root.knownAmps = initialKnownAmps;
            }
            root.selectedAmpIp = root.unwrap(properties.SelectedAmpIp, "");
        }

        onPropertiesChanged: (interfaceName, changed, invalidated) => {
            if ("Online" in changed) root.online = root.unwrap(changed.Online, root.online);
            if ("DeviceName" in changed) root.deviceName = root.unwrap(changed.DeviceName, root.deviceName);
            if ("AmpIp" in changed) root.ampIp = root.unwrap(changed.AmpIp, root.ampIp);
            // Guard against the late broadcast after togglePower()'s
            // optimistic write (see header). One click drives both, so
            // both share lastPowerChangeAtMs.
            if ("Power" in changed) {
                if (!root.within(root.lastPowerChangeAtMs, root.debounceMs)) {
                    root.power = root.unwrap(changed.Power, root.power);
                }
            }
            if ("PowerState" in changed) {
                root.daemonPowerState = root.unwrap(changed.PowerState, root.daemonPowerState);
                if (!root.within(root.lastPowerChangeAtMs, root.debounceMs)) {
                    root.powerState = root.unwrap(changed.PowerState, root.powerState);
                }
            }
            // Same guard for selectSource()'s optimistic write; one click
            // drives both fields.
            if (("ActiveSourceIndex" in changed || "ActiveSourceName" in changed)
                && !root.within(root.lastSourceChangeAtMs, root.debounceMs)) {
                if ("ActiveSourceIndex" in changed) root.activeSourceIndex = root.unwrap(changed.ActiveSourceIndex, root.activeSourceIndex);
                if ("ActiveSourceName" in changed) root.activeSourceName = root.unwrap(changed.ActiveSourceName, root.activeSourceName);
            }
            if ("Sources" in changed) root.fetchSourcesFresh();
            if ("SelectedAmpIp" in changed) root.selectedAmpIp = root.unwrap(changed.SelectedAmpIp, root.selectedAmpIp);
            if ("KnownAmps" in changed) root.fetchKnownAmpsFresh();
        }
    }

    // ---- background tint: the flyout's entire visible surface ----
    // The host Dialog has NoBackground, so there is no frame and mainItem
    // is the whole window: fill it edge to edge. A negative margin would
    // only push the rounded corners outside the window and clip them
    // square.
    //
    // Radius: the mockup's `.flyout{border-radius:16px}` (theme.radiusLg;
    // docs/DESIGN.md §7). AmpHeader's hover fill rounds its top corners to
    // the same radius so it can't paint square corners over these.
    //
    // colors.panelTintTop/Bottom are opaque base colours; the alpha is the
    // user's transparency setting. transparencySettings.withAlpha() reads
    // the live alpha on every call, so Apply/OK repaints this at once.
    Rectangle {
        anchors.fill: parent
        radius: root.theme.radiusLg
        antialiasing: true
        // No outer border: the v2 mockups draw none in either theme
        // (flyout :280).
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.transparencySettings.withAlpha(root.colors.panelTintTop) }
            GradientStop { position: 1.0; color: root.transparencySettings.withAlpha(root.colors.panelTintBottom) }
        }
    }

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        AmpHeader {
            id: ampHeader
            theme: root.theme
            colors: root.colors
            ampIp: root.ampIp
            headerName: root.headerName
            headerSub: root.headerSub
            online: root.online
            power: root.power
            powerState: root.powerState
            listOpen: root.ampListOpen
            onToggleRequested: root.ampListOpen = !root.ampListOpen
        }

        VolumeBlock {
            id: volumeBlock
            theme: root.theme
            colors: root.colors
            ampIp: root.ampIp
            volumeDb: root.pendingAmpState.volumeDb
            volumeSettings: root.volumeSettings
            transparencySettings: root.transparencySettings
            activeSourceName: root.activeSourceName
            // Same guarded mirror that arms the boot hold (see
            // onPowerStateChanged above) - slider and hold flip together.
            powerState: root.powerState
            onStepRequested: direction => root.stepVolume(direction)
            onSliderReleased: value => root.releaseVolume(value)
        }

        ActionRow {
            id: actionRow
            theme: root.theme
            colors: root.colors
            ampIp: root.ampIp
            muted: root.pendingAmpState.muted
            power: root.power
            powerState: root.powerState
            transparencySettings: root.transparencySettings
            onMuteToggleRequested: root.toggleMute()
            onPowerToggleRequested: root.togglePower()
        }

        SourceSelector {
            id: sourceSelector
            theme: root.theme
            colors: root.colors
            ampIp: root.ampIp
            sources: root.sources
            activeSourceIndex: root.activeSourceIndex
            activeSourceName: root.activeSourceName
            powerState: root.powerState
            transparencySettings: root.transparencySettings
            listOpen: root.sourceListOpen
            onToggleRequested: root.sourceListOpen = !root.sourceListOpen
        }

        // Plain section divider between the source selector and the
        // footer; lives in mainColumn, owned by neither component.
        Rectangle {
            objectName: "sourceFooterDivider"
            Layout.fillWidth: true
            height: 1
            color: root.colors.divider
        }

        Footer {
            id: footer
            theme: root.theme
            colors: root.colors
            ampIp: root.ampIp
            online: root.online
        }
    }

    // Amp list overlay - parented to the header so it anchors flush beneath
    // it (Popup positions relative to `parent`), content reparented into
    // the flyout window's Overlay (no new window). Owner never binds its
    // `visible`; drives open()/close() via onAmpListOpenChanged above and
    // listens to `closed`.
    AmpListOverlay {
        id: ampListOverlay
        parent: ampHeader
        theme: root.theme
        colors: root.colors
        knownAmps: root.knownAmps
        ampIp: root.ampIp
        transparencySettings: root.transparencySettings
        onClosed: root.ampListOpen = false
        onAmpChosen: ip => root.selectAmpByIp(ip)
    }

    // Source list overlay - parented to SourceSelector's row so it opens
    // upward from it (Popup positions relative to `parent`); same
    // owner-driven contract as AmpListOverlay above.
    SourceListOverlay {
        id: sourceListOverlay
        parent: sourceSelector.rowItem
        theme: root.theme
        colors: root.colors
        enabledSources: sourceSelector.enabledSources
        activeSourceIndex: root.activeSourceIndex
        transparencySettings: root.transparencySettings
        onClosed: root.sourceListOpen = false
        onSourceChosen: (index, name) => {
            root.sourceListOpen = false;
            root.selectSource(index, name);
        }
    }

    // ---- settings trigger (opens Plasma's configure dialog) ----
    Rectangle {
        id: settingsTrigger
        objectName: "settingsTrigger"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: 24
        height: 24
        radius: root.theme.radiusSm
        color: settingsTriggerArea.containsMouse ? root.colors.surface2 : "transparent"
        z: 10

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 15
            height: 15
            source: Qt.resolvedUrl("../icons/settings_gear.svg")
            isMask: true
            color: settingsTriggerArea.containsMouse ? root.colors.copperBright : root.colors.textFaint
        }

        MouseArea {
            id: settingsTriggerArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                Plasmoid.internalAction("configure")?.trigger()
            }
        }
    }
}
