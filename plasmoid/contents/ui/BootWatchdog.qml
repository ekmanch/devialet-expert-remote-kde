// Ends FlyoutContent.qml's "Booting" display when the daemon never does
// (2026-10-04). "Booting" disables the power button (togglePower() returns
// early) and only a daemon push used to end it, so anything that kept the
// daemon silent left the flyout stuck until plasmashell restarted. Found
// live: BeginPowerOnBoot was a no-op for a selected amp the daemon had not
// heard since login, PowerState never left "Off", and no signal came. The
// same holds when the daemon is down, restarts mid-boot (its deadline is
// in memory only) or the BeginPowerOnBoot call fails.
//
// Bounds every "Booting", whoever set it (the optimistic click, a daemon
// push, onRefreshed after a shell restart mid-boot): the timer runs for as
// long as `powerState` is "Booting" and `expired` fires when it elapses,
// or at once when the daemon's bus name vanishes or reappears while
// booting - a vanished daemon will never resolve the boot and a restarted
// one knows nothing of it (same reset rule as PendingAmpState.qml's
// daemonWatcher).
//
// timeoutMs, 22 s: the daemon resolves every boot it tracks within
// BOOT_TIMEOUT (20 s, interface.rs) plus one POLL_TICK (1 s, main.rs - the
// deadline is only checked on the receive loop's tick); the last second is
// for D-Bus delivery. Both clocks start at the same click
// (FlyoutContent.togglePower() calls BeginPowerOnBoot there), so a boot
// the daemon is tracking always resolves first and this never cuts a real
// boot short (measured 15.0-18.6 s across 21 boots). Firing late only
// costs stuck seconds in the failure case.
//
// The consumer assigns `fallbackState` to its power mirrors. It is "On"
// only if the daemon's last push said so (a push the consumer's 400 ms
// click guard dropped), otherwise "Off" - the daemon's own no-error-state
// timeout result. A stale "Booting" from a daemon that died mid-boot also
// maps to "Off".

import QtQuick
import org.kde.plasma.workspace.dbus as Dbus

QtObject {
    id: root

    // The state the consumer displays - bind it.
    property string powerState: "Off"
    // The daemon's last pushed PowerState, with no click guard applied.
    property string daemonPowerState: "Off"
    property int timeoutMs: 22000
    property string serviceName: "com.ekmanch.DevialetRemote"

    signal expired(string fallbackState, string reason)

    function expire(reason) {
        if (root.powerState !== "Booting") return;
        root.expired(root.daemonPowerState === "On" ? "On" : "Off", reason);
    }

    readonly property Timer timer: Timer {
        interval: root.timeoutMs
        repeat: false
        running: root.powerState === "Booting"
        onTriggered: root.expire("no boot result from the daemon within " + root.timeoutMs + " ms")
    }

    readonly property Dbus.DBusServiceWatcher daemonWatcher: Dbus.DBusServiceWatcher {
        busType: Dbus.BusType.Session
        watchedService: root.serviceName
        onRegisteredChanged: root.expire("daemon bus name " + (registered ? "reappeared" : "vanished"))
    }
}
