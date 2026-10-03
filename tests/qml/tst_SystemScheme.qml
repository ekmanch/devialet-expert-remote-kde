// QtTest for SystemScheme.qml (Phase 17.15.0), run by scripts/test-qml.sh
// against tests/qml/fakeportal.py on the private test bus - never the
// desktop's own portal. Each test sets the fake's reply behaviour through its
// control interface, then creates a fresh SystemScheme with a short timeout
// and a fallback colour of its choosing (white = light, black = dark), so
// every branch of the portal-reader contract is exercised:
// 1 / 2 / 0 / error / silence (timeout) / late reply / live SettingChanged
// (matching and non-matching), and the "starts dark" rule.

import QtQuick
import QtTest
import org.kde.plasma.workspace.dbus as Dbus
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "SystemScheme"

    readonly property int shortTimeout: 400

    Component {
        id: schemeComponent
        SystemScheme {}
    }

    property int ctlDone: 0

    // Call the fake portal's control interface and wait for it to return.
    function ctl(member, args) {
        const before = tc.ctlDone;
        Dbus.SessionBus.asyncCall(new Dbus.dbusMessage({
            service: "org.freedesktop.portal.Desktop",
            path: "/com/ekmanch/Test/FakePortal",
            interface: "com.ekmanch.Test.FakePortal1",
            member: member,
            arguments: args
        }), function (reply) { tc.ctlDone++; }, function (reply) { tc.ctlDone++; });
        tryVerify(function () { return tc.ctlDone > before; }, 2000, member + " acknowledged");
    }

    // uint32 arguments must be typed, or they are sent as doubles.
    function setReply(mode, value, delayMs) {
        ctl("SetReply", [mode, new Dbus.uint32(value), new Dbus.uint32(delayMs || 0)]);
    }
    function emitChanged(ns, key, value) {
        ctl("EmitChanged", [ns, key, new Dbus.uint32(value)]);
    }

    function make(fallback) {
        return createTemporaryObject(schemeComponent, tc, {
            timeoutMs: tc.shortTimeout,
            fallbackColor: fallback,
            context: "test"
        });
    }

    function test_portal_1_is_dark() {
        setReply("value", 1, 0);
        const s = make("white");
        tryCompare(s, "source", "portal");
        compare(s.dark, true);
    }

    function test_portal_2_is_light() {
        setReply("value", 2, 0);
        const s = make("black");
        tryCompare(s, "source", "portal");
        compare(s.dark, false);
    }

    function test_portal_0_uses_the_fallback_data() {
        return [{ tag: "light fallback", fallback: "white", dark: false },
                { tag: "dark fallback", fallback: "black", dark: true }];
    }
    function test_portal_0_uses_the_fallback(data) {
        setReply("value", 0, 0);
        const s = make(data.fallback);
        tryCompare(s, "source", "fallback");
        compare(s.dark, data.dark);
    }

    function test_unexpected_value_uses_the_fallback() {
        setReply("value", 7, 0);
        const s = make("white");
        tryCompare(s, "source", "fallback");
        compare(s.dark, false);
    }

    function test_portal_error_uses_the_fallback() {
        setReply("error", 0, 0);
        const s = make("white");
        tryCompare(s, "source", "fallback");
        compare(s.dark, false);
    }

    function test_starts_dark_and_falls_back_after_the_timeout() {
        setReply("silent", 0, 0);
        const s = make("white");
        // Before any answer: today's look, no flash of light.
        compare(s.dark, true);
        compare(s.source, "start");
        wait(tc.shortTimeout / 2);
        compare(s.source, "start", "still waiting before the timeout");
        tryCompare(s, "source", "fallback", tc.shortTimeout * 3);
        compare(s.dark, false);
    }

    function test_a_late_reply_still_wins() {
        setReply("value", 2, tc.shortTimeout * 3);   // light, but slower than the timeout
        const s = make("black");                     // fallback says dark
        tryCompare(s, "source", "fallback", tc.shortTimeout * 2);
        compare(s.dark, true);
        tryCompare(s, "source", "portal", tc.shortTimeout * 5);
        compare(s.dark, false);
    }

    function test_setting_changed_is_applied_live() {
        setReply("value", 1, 0);
        const s = make("black");
        tryCompare(s, "source", "portal");
        compare(s.dark, true);
        emitChanged("org.freedesktop.appearance", "color-scheme", 2);
        tryCompare(s, "dark", false);
        emitChanged("org.freedesktop.appearance", "color-scheme", 1);
        tryCompare(s, "dark", true);
    }

    function test_other_settings_are_ignored() {
        setReply("value", 1, 0);
        const s = make("white");
        tryCompare(s, "source", "portal");
        emitChanged("org.freedesktop.appearance", "accent-color", 2);
        emitChanged("org.kde.kdeglobals.General", "color-scheme", 2);
        wait(200);
        compare(s.dark, true);
        compare(s.source, "portal");
    }

    function test_setting_changed_to_0_uses_the_fallback() {
        setReply("value", 1, 0);
        const s = make("white");
        tryCompare(s, "source", "portal");
        emitChanged("org.freedesktop.appearance", "color-scheme", 0);
        tryCompare(s, "source", "fallback");
        compare(s.dark, false);
    }

    function test_a_timeout_does_not_override_a_portal_answer() {
        setReply("value", 2, 0);
        const s = make("black");
        tryCompare(s, "source", "portal");
        wait(tc.shortTimeout * 2);
        compare(s.source, "portal");
        compare(s.dark, false);
    }
}
