// QtTest for BootWatchdog.qml (2026-10-04), run by scripts/test-qml.sh.
// Guards the owner-reported stuck "Booting…": a boot result that never
// arrives from the daemon must still end the state. The watchdog is driven
// the way FlyoutContent.qml drives it - `powerState` is the displayed
// state, `daemonPowerState` the daemon's last push - with a short timeout.
// The bus-name cases point the watcher at fakeamp.py's name (owned on this
// private bus) and at a name nobody owns.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "BootWatchdog"

    readonly property int timeoutMs: 150
    readonly property string ownedName: "com.ekmanch.DevialetRemote"
    readonly property string unownedName: "com.ekmanch.DevialetRemote.NotRunning"

    Component {
        id: watchdogComponent
        BootWatchdog { timeoutMs: tc.timeoutMs }
    }

    property var watchdog: null

    SignalSpy { id: expiredSpy; signalName: "expired" }

    function init() {
        watchdog = watchdogComponent.createObject(tc);
        expiredSpy.target = watchdog;
        // Let the watcher learn that the fake daemon's name is owned.
        tryCompare(watchdog.daemonWatcher, "registered", true, 2000);
        expiredSpy.clear();
    }

    function cleanup() {
        watchdog.destroy();
        watchdog = null;
    }

    // The 2026-10-04 report: optimistic "Booting", daemon stays at "Off"
    // and sends nothing.
    function test_a_boot_result_that_never_arrives_ends_booting_as_off() {
        watchdog.powerState = "Booting";
        wait(timeoutMs / 2);
        compare(expiredSpy.count, 0, "must not fire before the timeout");
        tryCompare(expiredSpy, "count", 1, timeoutMs * 4);
        compare(expiredSpy.signalArguments[0][0], "Off");
    }

    function test_a_daemon_result_before_the_timeout_stops_it() {
        watchdog.powerState = "Booting";
        wait(timeoutMs / 2);
        watchdog.daemonPowerState = "On";
        watchdog.powerState = "On";
        wait(timeoutMs * 2);
        compare(expiredSpy.count, 0);
    }

    function test_not_booting_never_fires() {
        watchdog.powerState = "On";
        watchdog.powerState = "Off";
        wait(timeoutMs * 2);
        compare(expiredSpy.count, 0);
    }

    // The daemon said "On" inside the consumer's 400 ms click guard, which
    // dropped it: the fallback is what the daemon last said.
    function test_falls_back_to_on_when_the_daemon_last_said_on() {
        watchdog.powerState = "Booting";
        watchdog.daemonPowerState = "On";
        tryCompare(expiredSpy, "count", 1, timeoutMs * 4);
        compare(expiredSpy.signalArguments[0][0], "On");
    }

    // A daemon that reported "Booting" and then died: its last push must
    // not keep the state alive.
    function test_a_stale_daemon_booting_falls_back_to_off() {
        watchdog.daemonPowerState = "Booting";
        watchdog.powerState = "Booting";
        tryCompare(expiredSpy, "count", 1, timeoutMs * 4);
        compare(expiredSpy.signalArguments[0][0], "Off");
    }

    // Each "Booting" gets a full timeout, and one expiry fires once.
    function test_a_second_boot_gets_a_full_timeout() {
        watchdog.powerState = "Booting";
        tryCompare(expiredSpy, "count", 1, timeoutMs * 4);
        watchdog.powerState = "Off";     // what the consumer does on expired
        wait(timeoutMs * 2);
        compare(expiredSpy.count, 1);
        watchdog.powerState = "Booting";
        wait(timeoutMs / 2);
        compare(expiredSpy.count, 1);
        tryCompare(expiredSpy, "count", 2, timeoutMs * 4);
    }

    function test_daemon_name_vanishing_while_booting_ends_it_at_once() {
        watchdog.timeoutMs = 60000;
        watchdog.powerState = "Booting";
        watchdog.serviceName = unownedName;
        tryCompare(expiredSpy, "count", 1, 2000);
        compare(expiredSpy.signalArguments[0][0], "Off");
    }

    function test_daemon_name_reappearing_while_booting_ends_it_at_once() {
        watchdog.timeoutMs = 60000;
        watchdog.serviceName = unownedName;
        tryCompare(watchdog.daemonWatcher, "registered", false, 2000);
        expiredSpy.clear();
        watchdog.powerState = "Booting";
        watchdog.serviceName = ownedName;
        tryCompare(expiredSpy, "count", 1, 2000);
        compare(expiredSpy.signalArguments[0][0], "Off");
    }

    function test_daemon_name_changes_while_not_booting_do_nothing() {
        watchdog.serviceName = unownedName;
        tryCompare(watchdog.daemonWatcher, "registered", false, 2000);
        watchdog.serviceName = ownedName;
        tryCompare(watchdog.daemonWatcher, "registered", true, 2000);
        compare(expiredSpy.count, 0);
    }
}
