// QtTest unit tests for the real PendingAmpState.qml (plasmoid/contents/ui),
// run by scripts/test-qml.sh on a private session bus with
// tools/flyout-harness/fakeamp.py owning the daemon's name purely as a
// sink for NotifyVolumeCommand (a failed call would roll volumeDb back and
// corrupt the re-target cases). The daemon's pushes are simulated by
// emitting ampProps.propertiesChanged() directly, one property per call,
// in emit_all() order (interface.rs): that is the exact message shape the
// real daemon produces, and the ordering is what the 2026-09-20 regression
// hinged on - see PendingAmpState.qml's header.
//
// Each test arms the hold itself the way FlyoutContent.onPowerStateChanged
// does (beginBootHold), because the "On" that triggers it is delivered to
// FlyoutContent's own subscription before this object sees the same
// packet's VolumeRaw.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "PendingAmpState"

    readonly property string ip: "10.255.255.1"
    readonly property string iface: "com.ekmanch.DevialetRemote.Amp1"
    readonly property int timeoutMs: 1500

    Component {
        id: stateComponent
        PendingAmpState {}
    }

    property var state: null

    // One PropertiesChanged message carrying one property, as the daemon
    // sends them.
    function push(changed) {
        state.ampProps.propertiesChanged(iface, changed, []);
    }

    // One status broadcast as the daemon relays it: VolumeRaw (unmasked
    // byte) before VolumeDb (possibly masked by a pending command).
    function pushPacket(raw, db) {
        push({ VolumeRaw: raw });
        push({ VolumeDb: db });
    }

    function init() {
        state = stateComponent.createObject(tc);
        // Let the fake daemon's GetAll (onRefreshed, AmpIp "") land before
        // the test drives its own state.
        wait(300);
        push({ AmpIp: ip });
        pushPacket(145, -25);   // pre-boot: last standby broadcast
        compare(state.ampIp, ip);
        compare(state.volumeDb, -25);
        compare(state.bootHoldIp, "");
    }

    function cleanup() {
        // Let any in-flight NotifyVolumeCommand reply land while its
        // callbacks still have an object to call forgetOwn() on.
        wait(100);
        state.destroy();
        state = null;
    }

    // The 2026-09-20 regression: amp powered off at exactly the startup
    // target, so the first power-on packet's stale byte matches it.
    function test_stale_first_packet_matching_target_does_not_release() {
        state.beginBootHold(ip, -40);
        compare(state.volumeDb, -40);
        verify(!state.bootHoldSent);

        pushPacket(115, -40);   // first On packet: pre-shutdown byte == target
        compare(state.bootHoldIp, ip, "a matching byte before any send must not release the hold");
        compare(state.volumeDb, -40);

        pushPacket(111, -42);   // ~200 ms later: the amp's own misreport
        compare(state.bootHoldIp, ip);
        compare(state.volumeDb, -40, "the misreport must stay masked");
        compare(state.lastRealVolumeDb, -42, "but must be recorded as the last real value");

        state.notifyVolume(-40);   // FlyoutContent's startup send at +500 ms
        verify(state.bootHoldSent);
        compare(state.volumeDb, -40);

        pushPacket(111, -40);   // daemon's 400 ms masked echo; real byte still 111
        compare(state.bootHoldIp, ip, "the masked VolumeDb echo proves nothing");

        pushPacket(115, -40);   // the amp confirms the send
        compare(state.bootHoldIp, "", "a matching byte after the send releases the hold");
        compare(state.volumeDb, -40);
        verify(!state.bootHoldSent);
    }

    // Formerly asserted the other way round ("target == misreport confirms
    // immediately", TODO.md Phase 8.0.1 driver run): a target equal to the
    // amp's own post-boot value is still only confirmed after the send.
    function test_target_equal_to_misreport_waits_for_the_send() {
        state.beginBootHold(ip, -42);
        pushPacket(111, -42);
        compare(state.bootHoldIp, ip);
        state.notifyVolume(-42);
        pushPacket(111, -42);
        compare(state.bootHoldIp, "");
        compare(state.volumeDb, -42);
    }

    function test_user_retarget_inside_the_window_counts_as_the_send() {
        state.beginBootHold(ip, -40);
        state.notifyVolume(-30);   // panel wheel / slider before the startup send
        compare(state.bootHoldDb, -30);
        compare(state.volumeDb, -30);
        verify(state.bootHoldSent);

        pushPacket(115, -40);   // the configured value would no longer confirm
        compare(state.bootHoldIp, ip);
        compare(state.volumeDb, -30);

        pushPacket(135, -30);   // only the user's value does
        compare(state.bootHoldIp, "");
        compare(state.volumeDb, -30);
    }

    function test_rearming_clears_the_sent_flag() {
        state.beginBootHold(ip, -40);
        state.notifyVolume(-40);
        verify(state.bootHoldSent);
        state.beginBootHold(ip, -40);
        verify(!state.bootHoldSent);
        pushPacket(115, -40);
        compare(state.bootHoldIp, ip);
    }

    function test_volumedb_pushes_apply_again_once_released() {
        state.beginBootHold(ip, -40);
        state.notifyVolume(-40);
        pushPacket(115, -40);
        compare(state.bootHoldIp, "");
        pushPacket(125, -35);   // physical remote afterwards
        compare(state.volumeDb, -35);
    }

    // Fallback with nothing ever sent: bounded from arming.
    function test_fallback_runs_from_arming_when_nothing_is_sent() {
        state.beginBootHold(ip, -40);
        pushPacket(111, -42);
        wait(timeoutMs - 300);
        compare(state.bootHoldIp, ip, "still held before the deadline");
        compare(state.volumeDb, -40);
        wait(600);
        compare(state.bootHoldIp, "", "released by the fallback");
        compare(state.volumeDb, -42, "fallback shows the last real value");
    }

    // Fallback with a send: the full allowance is measured from the send,
    // not from arming (the send itself is 500 ms after "On").
    function test_fallback_restarts_from_the_send() {
        state.beginBootHold(ip, -40);
        pushPacket(111, -42);
        wait(timeoutMs - 300);
        state.notifyVolume(-40);           // the startup send, late in the window
        wait(600);                          // past the original deadline
        compare(state.bootHoldIp, ip, "the send restarted the allowance");
        compare(state.volumeDb, -40);
        pushPacket(111, -42);               // a tick reverting the daemon's expired mask
        compare(state.volumeDb, -40, "still masked while the restarted allowance runs");
        wait(timeoutMs - 600 + 300);        // past the restarted deadline
        compare(state.bootHoldIp, "", "released by the fallback after the send's allowance");
        compare(state.volumeDb, -42, "fallback shows the amp's real (misreported) value");
    }

    function test_fallback_does_not_fire_after_a_confirmation() {
        state.beginBootHold(ip, -40);
        state.notifyVolume(-40);
        pushPacket(115, -40);
        compare(state.bootHoldIp, "");
        pushPacket(125, -35);
        wait(timeoutMs + 300);
        compare(state.volumeDb, -35, "no stale fallback write after release");
    }

    function test_amp_ip_change_ends_the_hold_but_a_re_emit_does_not() {
        state.beginBootHold(ip, -40);
        push({ AmpIp: ip });        // every emit_all() re-sends AmpIp unchanged
        compare(state.bootHoldIp, ip);
        push({ AmpIp: "10.0.0.2" });
        compare(state.bootHoldIp, "");
        verify(!state.bootHoldSent);
    }
}
