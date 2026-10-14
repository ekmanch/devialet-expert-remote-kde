// The one shared consumer of the daemon's resolved VolumeDb/Muted
// (pending-or-confirmed; the daemon owns pending state, docs/DESIGN.md
// §3). Instantiated once at main.qml's root and forwarded as a
// `required property`, so every surface (panel icon, flyout, OSD,
// tooltip) reads the same value.
//
// Scope: the D-Bus subscription is interface-level, but only AmpIp,
// VolumeDb, Muted and VolumeRaw are processed here. VolumeRaw is the
// amp's unmasked status byte, used for the post-boot hold's
// confirmation and exposed as `confirmedVolumeDb` for the chime. Keep
// other properties out of this file.
//
// Post-boot volume hold (`beginBootHold`/`endBootHold`, `bootHold*`).
// After a boot the amp's broadcast first carries the pre-shutdown byte,
// then ~200 ms later a value 2 dB low (raw 111 = -42.0 while the panel
// reads -40) that stays until a volume command is sent (gotcha #8).
// FlyoutContent sends the startup volume 500 ms after "On" (gotcha #9),
// confirmed 96-199 ms later; without the hold every surface would show
// -42 for ~300-500 ms and then jump. It lives here, not in
// FlyoutContent, because every surface reads volumeDb from this object.
//
// FlyoutContent arms the hold on Booting -> On, which shows the target
// at once. While held, VolumeDb pushes are recorded (`lastRealVolumeDb`)
// but not applied. Any notifyVolume() re-targets the hold to that value
// and shows it, so the user always wins; the deferred startup send reads
// `bootHoldDb`, so the amp gets the same value. The hold ends when a
// VolumeRaw push decodes to `bootHoldDb` after a send - not on the
// daemon's echo of our own NotifyVolumeCommand, which fires at the send.
// A match before any send does not count: the first power-on packet
// carries the pre-shutdown byte, which equals the target whenever the
// amp was switched off at the startup volume, and PowerState (which
// arms the hold) arrives before that packet's VolumeRaw (gotcha #8).
// Fallback: `bootHoldTimeoutMs` (1500 ms: 500 ms send + ~200 ms confirm
// + the >400 ms late-application allowance, rounded) runs from arming
// until a send, then from the latest send, and shows the last real
// value. The hold also ends on an AmpIp change and, via FlyoutContent,
// on a power-off click or boot timeout. Its console.log lines (a
// handful per boot) stay on so the journal shows which path released
// it.
//
// Apart from the hold and the echo guard (next to noteVolumeDb), this
// file never resolves pending-vs-confirmed itself; the daemon does.
//
// External-command signals. The daemon emits `VolumeCommandNotified` /
// `MuteCommandNotified` from NotifyVolumeCommand/NotifyMuteCommand, so a
// command from another tool (e.g. an MPV script) can show the OSD;
// changes the daemon only observes from the amp never emit them. Every
// widget-originated Notify* call goes through notifyVolume/notifyMute
// here, so this is the one place that can tell our own echo from an
// external call: `ownInFlight` remembers each call, the signal handler
// consumes a matching entry silently, and only an unmatched signal is
// re-emitted as `externalVolumeCommand`/`externalMuteCommand` for
// CompactRepresentation's toast. The daemon emits the signal before
// replying, so the echo normally consumes the entry first; reply
// callbacks only forget entries no signal matched (unknown IP, an old
// daemon), and they forget by id, never by value, because two calls
// with equal values can be in flight (fast scrolling at a clamp edge).
// Matching by sender is not possible: QML cannot read plasmashell's own
// unique bus name.
//
// A plain QtObject, not `pragma Singleton`: this KPackage has no qmldir
// module for a real singleton.

import QtQml
import org.kde.plasma.workspace.dbus as Dbus

QtObject {
    id: root

    readonly property string serviceName: "com.ekmanch.DevialetRemote"
    readonly property string objectPath: "/com/ekmanch/DevialetRemote/Amp"
    readonly property string interfaceName: "com.ekmanch.DevialetRemote.Amp1"

    // Verbose lifecycle logging; off unless debugging.
    readonly property bool debugLogging: false

    property string ampIp: ""
    property var volumeDb: undefined
    property bool muted: false

    // PC-originated commands from a caller other than this widget (see the
    // header): the daemon's VolumeCommandNotified/MuteCommandNotified
    // minus our own echoes. CompactRepresentation shows the OSD on these.
    signal externalVolumeCommand(real db)
    signal externalMuteCommand(bool muted)

    // Calls this widget itself has made to Notify*Command and not yet
    // seen echoed back as a signal. Plain JS array of {id, kind, value}
    // (kind "volume" | "mute"); nothing binds to it, so in-place mutation
    // is fine. Signals match by value - exact: a double sent as a D-Bus `d`
    // comes back bit-identical, a bool trivially - and entries with equal
    // values are interchangeable there. Reply cleanup matches by id, so a
    // call only ever removes its own entry (see the header).
    property var ownInFlight: []
    property int ownNextId: 0

    // Returns the entry's id, for the call's reply callbacks.
    function rememberOwn(kind, value) {
        const id = root.ownNextId++;
        root.ownInFlight.push({ id: id, kind: kind, value: value });
        if (root.debugLogging) console.log("[PendingAmpState] remembered own", kind, value, "id", id);
        return id;
    }

    // Signal-side match: removes the oldest entry with this value; true if
    // there was one.
    function consumeOwn(kind, value) {
        for (let i = 0; i < root.ownInFlight.length; i++) {
            const entry = root.ownInFlight[i];
            if (entry.kind === kind && entry.value === value) {
                root.ownInFlight.splice(i, 1);
                return true;
            }
        }
        return false;
    }

    // Reply-time cleanup for an entry no signal matched (see the header):
    // removes the entry `rememberOwn` returned `id` for, if its echo has not
    // already consumed it. Never touches another call's entry.
    function forgetEntry(id) {
        for (let i = 0; i < root.ownInFlight.length; i++) {
            const entry = root.ownInFlight[i];
            if (entry.id === id) {
                root.ownInFlight.splice(i, 1);
                if (root.debugLogging) console.log("[PendingAmpState] forgot unechoed own", entry.kind, entry.value, "id", id);
                return;
            }
        }
    }

    // Post-boot hold state (see the header). bootHoldIp "" = not held.
    // bootHoldDb = the value currently shown (startup volume, or the
    // user's latest change). lastRealVolumeDb = the latest daemon VolumeDb
    // push, kept whether held or not; shown if the hold times out.
    // Tracked here because Plasma.DBusProperties has no refresh().
    property string bootHoldIp: ""
    property var bootHoldDb: undefined
    // True once a volume command has been sent while held (notifyVolume);
    // a VolumeRaw match releases the hold only after that.
    property bool bootHoldSent: false
    property var lastRealVolumeDb: undefined
    // (VolumeRaw - 195) / 2, the amp's real last-broadcast dB for the
    // chime - not volumeDb, which is optimistic and then daemon-masked for
    // 400 ms after every command. undefined until an amp is selected and
    // has broadcast. Written only by noteVolumeRaw().
    property var confirmedVolumeDb: undefined
    readonly property int bootHoldTimeoutMs: 1500

    // Named property, not a bare child - QtObject has no default property
    // (same reason as `ampProps` below).
    readonly property Timer bootHoldTimer: Timer {
        interval: root.bootHoldTimeoutMs
        repeat: false
        onTriggered: {
            if (root.bootHoldIp === "") return;
            console.log("[PendingAmpState] boot hold timed out unconfirmed (sent:", root.bootHoldSent + "); falling back to", root.lastRealVolumeDb);
            const fallback = root.lastRealVolumeDb;
            root.endBootHold();
            if (fallback !== undefined) root.volumeDb = fallback;
        }
    }

    // Arm the hold: show `db` immediately and keep showing it until the
    // amp's broadcast confirms it (a VolumeRaw match after a send), or
    // bootHoldTimeoutMs elapses - measured from arming until a send
    // happens, then from the latest send. A user re-target (notifyVolume)
    // keeps the hold and counts as the send. Re-arming while held just
    // re-targets and clears the sent flag.
    function beginBootHold(ip, db) {
        if (ip === "" || db === undefined) return;
        root.bootHoldIp = ip;
        root.bootHoldDb = db;
        root.bootHoldSent = false;
        root.volumeDb = db;
        root.bootHoldTimer.restart();
        console.log("[PendingAmpState] boot hold armed for", ip, "at", db);
    }

    function endBootHold() {
        root.bootHoldTimer.stop();
        root.bootHoldIp = "";
        root.bootHoldDb = undefined;
        root.bootHoldSent = false;
    }

    // Confirmation check for the hold - the daemon's VolumeRaw is the
    // amp's real status byte, unmasked by pending commands (interface.rs),
    // decoded with the protocol crate's own formula (status.rs
    // volume_db()). bootHoldDb is a whole-dB config value or a clamp of
    // one, and raw decodes to a multiple of 0.5, so `===` is exact.
    function noteVolumeRaw(raw) {
        // Expose the decoded byte before the hold's early return. The
        // daemon emits VolumeRaw=0 with AmpIp="" when no amp is selected
        // (would decode to -97.5), hence the ampIp guard; noteAmpIp always
        // runs first in both handlers below.
        root.confirmedVolumeDb = (raw === undefined || root.ampIp === "") ? undefined : (raw - 195) / 2;
        if (root.bootHoldIp === "" || raw === undefined) return;
        if ((raw - 195) / 2 !== root.bootHoldDb) return;
        // A match before any send is the amp's pre-shutdown or own
        // startup byte, not a confirmation of ours (see header). Keep
        // holding; the fallback timer still bounds it.
        if (!root.bootHoldSent) {
            console.log("[PendingAmpState] boot hold: VolumeRaw", raw, "matches the target before any send - ignored");
            return;
        }
        console.log("[PendingAmpState] boot hold released: VolumeRaw", raw, "confirmed", root.bootHoldDb);
        root.endBootHold();
    }

    // VolumeDb push from the daemon: always remembered, applied only when
    // not held (the hold is the whole point - see header) and when no own
    // volume call is awaiting its reply (echo guard below).
    function noteVolumeDb(db) {
        root.lastRealVolumeDb = db;
        if (root.bootHoldIp === "" && root.ownVolumeCallsPending === 0) root.volumeDb = db;
    }

    // Echo guard. NotifyVolumeCommand makes the daemon push VolumeDb = that
    // call's value before replying. When a later notch has already gone
    // out, call N's push would rewind volumeDb - the base stepVolume()
    // builds the next notch on - so the next notch repeated or lost a
    // step. While any own volume call is unreplied, pushes are only
    // recorded (lastRealVolumeDb); once the last reply lands (after all
    // of those calls' pushes), volumeDb is reconciled with the daemon's
    // latest value, which also picks up a real change made meanwhile.
    //
    // The count must never stick: the callbacks decrement first; a
    // watchdog resets it if the latest send has gone ownVolumeWatchdogMs
    // without every reply (round trip measured ~1 ms; QtDBus's own call
    // timeout is 25 s); the daemon's bus name vanishing or reappearing
    // resets it too. A reset bumps the epoch, so late replies from
    // abandoned calls can't lower a newer burst's count.
    property int ownVolumeCallsPending: 0
    property int ownVolumeEpoch: 0
    property int ownVolumeWatchdogMs: 3000

    readonly property Timer ownVolumeWatchdog: Timer {
        interval: root.ownVolumeWatchdogMs
        repeat: false
        onTriggered: {
            if (root.ownVolumeCallsPending > 0) root.resetOwnVolumeCalls("no reply within " + root.ownVolumeWatchdogMs + " ms");
        }
    }

    // Plasma's DBusServiceWatcher (org.kde.plasma.workspace.dbus,
    // dbusplugin.qmltypes: busType/watchedService/registered). Either
    // direction resets: replies to calls made to a vanished daemon will
    // never come, and a restarted one knows nothing of them.
    readonly property Dbus.DBusServiceWatcher daemonWatcher: Dbus.DBusServiceWatcher {
        busType: Dbus.BusType.Session
        watchedService: root.serviceName
        onRegisteredChanged: {
            if (root.ownVolumeCallsPending > 0) root.resetOwnVolumeCalls("daemon bus name " + (registered ? "reappeared" : "vanished"));
        }
    }

    // Returns the epoch the call's callbacks hand back to endOwnVolumeCall.
    function beginOwnVolumeCall() {
        root.ownVolumeCallsPending += 1;
        root.ownVolumeWatchdog.restart();
        return root.ownVolumeEpoch;
    }

    // First statement of both reply callbacks. True when this reply
    // brought the count to 0 - the caller then reconciles last.
    function endOwnVolumeCall(epoch) {
        if (epoch !== root.ownVolumeEpoch || root.ownVolumeCallsPending === 0) return false;
        root.ownVolumeCallsPending -= 1;
        if (root.ownVolumeCallsPending > 0) return false;
        root.ownVolumeWatchdog.stop();
        return true;
    }

    function resetOwnVolumeCalls(reason) {
        console.log("[WARN] [PendingAmpState] resetting", root.ownVolumeCallsPending, "unreplied volume call(s):", reason);
        root.ownVolumeCallsPending = 0;
        root.ownVolumeEpoch += 1;
        root.ownVolumeWatchdog.stop();
        root.reconcileVolume();
    }

    function reconcileVolume() {
        if (root.bootHoldIp === "" && root.lastRealVolumeDb !== undefined) root.volumeDb = root.lastRealVolumeDb;
    }

    // AmpIp from the daemon: a *change* while held ends the hold (the
    // held value belongs to the amp that booted, not the new one). Every
    // emit_all() re-sends an unchanged AmpIp, so compare, don't just
    // react to the key being present.
    function noteAmpIp(ip) {
        if (root.bootHoldIp !== "" && ip !== root.bootHoldIp) root.endBootHold();
        root.ampIp = ip;
    }

    // Same helper as in CompactRepresentation and FlyoutContent;
    // duplicated on purpose, it is small and stable.
    function unwrap(prop, fallback) {
        if (prop === undefined || prop === null) return fallback;
        if (typeof prop === "object" && prop.value !== undefined) return prop.value;
        return prop;
    }

    // Both functions write volumeDb/muted synchronously, before the async
    // D-Bus call, so callers can use them as the accumulation base for
    // rapid repeats (the next notch needs the value set this tick).
    //
    // Rollback on failure: the resolve/reject callbacks are single-shot
    // and mutually exclusive (plasma-workspace dbusconnection.cpp), so a
    // rollback cannot double-fire or race a late success. Without it a
    // failed call (daemon down) would leave an unconfirmed value shown.
    function notifyVolume(db) {
        if (root.ampIp === "") return;
        // While held, every notifyVolume is a real command going out (the
        // startup send or the user's own): it re-targets the hold, makes a
        // later matching VolumeRaw count as confirmation and restarts the
        // fallback timer (see header).
        if (root.bootHoldIp !== "") {
            root.bootHoldDb = db;
            root.bootHoldSent = true;
            root.bootHoldTimer.restart();
            console.log("[PendingAmpState] boot hold: volume", db, "sent while held; confirmation now accepted");
        }
        const previous = root.volumeDb;
        root.volumeDb = db;
        const ownId = root.rememberOwn("volume", db);
        const epoch = root.beginOwnVolumeCall();
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: root.serviceName,
                path: root.objectPath,
                interface: root.interfaceName,
                member: "NotifyVolumeCommand",
                arguments: [root.ampIp, db]
            }),
            function (reply) {
                const settled = root.endOwnVolumeCall(epoch);
                root.forgetEntry(ownId);
                if (reply.isError) {
                    root.volumeDb = previous;
                    console.log("[WARN] NotifyVolumeCommand call returned a D-Bus error:", JSON.stringify(reply.error));
                }
                if (settled) root.reconcileVolume();
            },
            function (reply) {
                const settled = root.endOwnVolumeCall(epoch);
                root.forgetEntry(ownId);
                root.volumeDb = previous;
                console.log("[WARN] NotifyVolumeCommand call failed:", JSON.stringify(reply.error));
                if (settled) root.reconcileVolume();
            }
        );
    }

    function notifyMute(muted) {
        if (root.ampIp === "") return;
        const previous = root.muted;
        root.muted = muted;
        const ownId = root.rememberOwn("mute", muted);
        Dbus.SessionBus.asyncCall(
            new Dbus.dbusMessage({
                service: root.serviceName,
                path: root.objectPath,
                interface: root.interfaceName,
                member: "NotifyMuteCommand",
                arguments: [root.ampIp, muted]
            }),
            function (reply) {
                root.forgetEntry(ownId);
                if (reply.isError) {
                    root.muted = previous;
                    console.log("[WARN] NotifyMuteCommand call returned a D-Bus error:", JSON.stringify(reply.error));
                }
            },
            function (reply) {
                root.forgetEntry(ownId);
                root.muted = previous;
                console.log("[WARN] NotifyMuteCommand call failed:", JSON.stringify(reply.error));
            }
        );
    }

    // A named property, not a bare child: QtObject has no default
    // property in Qt 6 (Theme.qml does the same for its FontLoaders).
    readonly property Dbus.Properties ampProps: Dbus.Properties {
        busType: Dbus.BusType.Session
        service: root.serviceName
        path: root.objectPath
        iface: root.interfaceName

        onRefreshed: {
            root.noteAmpIp(root.unwrap(properties.AmpIp, ""));
            root.noteVolumeRaw(root.unwrap(properties.VolumeRaw, undefined));
            root.noteVolumeDb(root.unwrap(properties.VolumeDb, undefined));
            root.muted = root.unwrap(properties.Muted, false);
            if (root.debugLogging) {
                console.log("[PendingAmpState] onRefreshed", root.ampIp, root.volumeDb, root.muted);
            }
        }

        // Interface-level subscription: other properties arrive too and
        // are ignored (see header). Order matches the daemon's emit_all():
        // AmpIp, then VolumeRaw, then VolumeDb, so a confirming raw byte
        // ends the hold before the same emission's VolumeDb is considered.
        onPropertiesChanged: (interfaceName, changed, invalidated) => {
            if ("AmpIp" in changed) root.noteAmpIp(root.unwrap(changed.AmpIp, root.ampIp));
            if ("VolumeRaw" in changed) root.noteVolumeRaw(root.unwrap(changed.VolumeRaw, undefined));
            if ("VolumeDb" in changed) root.noteVolumeDb(root.unwrap(changed.VolumeDb, root.volumeDb));
            if ("Muted" in changed) root.muted = root.unwrap(changed.Muted, root.muted);
            if (root.debugLogging && (("AmpIp" in changed) || ("VolumeDb" in changed) || ("Muted" in changed))) {
                console.log("[PendingAmpState] onPropertiesChanged", root.ampIp, root.volumeDb, root.muted);
            }
        }
    }

    // Subscription to the daemon's two custom signals (see the header).
    // Plasma's SignalWatcher dispatches each signal of `iface` to a JS
    // function named "dbus" + <member>, arguments positionally, so the two
    // function names below are fixed by the D-Bus signal names. A named
    // property for the same reason as ampProps above.
    readonly property Dbus.SignalWatcher commandSignals: Dbus.SignalWatcher {
        busType: Dbus.BusType.Session
        service: root.serviceName
        path: root.objectPath
        iface: root.interfaceName

        function dbusVolumeCommandNotified(ip, db) {
            root.handleCommandSignal("volume", root.unwrap(ip, ""), root.unwrap(db, undefined));
        }

        function dbusMuteCommandNotified(ip, muted) {
            root.handleCommandSignal("mute", root.unwrap(ip, ""), root.unwrap(muted, undefined));
        }
    }

    // A command aimed at another amp than the one this widget shows is
    // ignored outright; our own echo is consumed silently; anything else
    // is a genuinely external command.
    function handleCommandSignal(kind, ip, value) {
        if (value === undefined || ip !== root.ampIp) return;
        if (root.consumeOwn(kind, value)) {
            if (root.debugLogging) console.log("[PendingAmpState] own echo consumed", kind, value);
            return;
        }
        if (root.debugLogging) console.log("[PendingAmpState] external", kind, value);
        if (kind === "volume") root.externalVolumeCommand(value);
        else root.externalMuteCommand(value);
    }
}
