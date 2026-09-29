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

    SignalSpy { id: externalVolumeSpy; signalName: "externalVolumeCommand" }
    SignalSpy { id: externalMuteSpy; signalName: "externalMuteCommand" }

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
        externalVolumeSpy.target = state;
        externalMuteSpy.target = state;
        externalVolumeSpy.clear();
        externalMuteSpy.clear();
    }

    function cleanup() {
        // Let any in-flight NotifyVolumeCommand reply land while its
        // callbacks still have an object to call forgetEntry() on.
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
        // Delivered before the send's reply here, so the echo guard holds
        // it until that reply lands, then reconciles to it.
        tryCompare(state, "volumeDb", -35);
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

    // 2026-09-29 regression: fast scrolling on the flyout slider past the
    // ceiling sends the clamped value twice before the first reply lands.
    // Driven in the real daemon's order (signal N before reply N, measured
    // in Phase 16.0.0's soak). Reply #1 used to forget by value and so
    // deleted call #2's entry, and call #2's echo then showed the OSD.
    function test_duplicate_volume_in_flight_is_not_external() {
        const e1 = state.rememberOwn("volume", -20);
        const e2 = state.rememberOwn("volume", -20);
        state.handleCommandSignal("volume", ip, -20);
        state.forgetEntry(e1);
        state.handleCommandSignal("volume", ip, -20);
        state.forgetEntry(e2);
        compare(externalVolumeSpy.count, 0, "own echo misattributed as external");
        compare(state.ownInFlight.length, 0);
    }

    // Same shape for mute: scrolling fast while muted sends `mute false`
    // once per notch until the unmute lands.
    function test_duplicate_mute_in_flight_is_not_external() {
        const e1 = state.rememberOwn("mute", false);
        const e2 = state.rememberOwn("mute", false);
        state.handleCommandSignal("mute", ip, false);
        state.forgetEntry(e1);
        state.handleCommandSignal("mute", ip, false);
        state.forgetEntry(e2);
        compare(externalMuteSpy.count, 0, "own echo misattributed as external");
        compare(state.ownInFlight.length, 0);
    }

    // The case reply cleanup exists for: no echo ever arrives (unknown-ip
    // no-op, old daemon). The reply removes its own entry, so a later
    // external command with the same value still shows.
    function test_unechoed_call_is_forgotten_by_its_own_reply() {
        const e1 = state.rememberOwn("volume", -30);
        state.forgetEntry(e1);
        compare(state.ownInFlight.length, 0);
        state.handleCommandSignal("volume", ip, -30);
        compare(externalVolumeSpy.count, 1);
    }

    // Control: an external command with a different value while our own
    // call is in flight still shows, and our echo is still swallowed.
    function test_external_value_during_own_call_is_external() {
        const e1 = state.rememberOwn("volume", -25);
        state.handleCommandSignal("volume", ip, -31);
        compare(externalVolumeSpy.count, 1);
        compare(externalVolumeSpy.signalArguments[0][0], -31);
        state.handleCommandSignal("volume", ip, -25);
        state.forgetEntry(e1);
        compare(externalVolumeSpy.count, 1);
        compare(state.ownInFlight.length, 0);
    }

    // Parked item fixed 2026-09-29: the daemon pushes VolumeDb = each
    // call's own value inside NotifyVolumeCommand, before replying. When a
    // later notch has already been sent, call 1's echo used to rewind
    // volumeDb (the base the next step builds on) to call 1's value -
    // measured as 14 direction reversals in a pre-rate-limit burst. Both
    // pushes are delivered here before either reply can land.
    function test_own_echo_does_not_rewind_a_newer_optimistic_value() {
        state.notifyVolume(-30);
        state.notifyVolume(-29);
        push({ VolumeDb: -30 });   // call 1's echo
        compare(state.volumeDb, -29, "call 1's echo must not pull the base back");
        push({ VolumeDb: -29 });   // call 2's echo
        compare(state.volumeDb, -29);
        wait(100);                 // both replies land; reconcile
        compare(state.volumeDb, -29);
        compare(state.ownVolumeCallsPending, 0);
    }

    // A genuine change (physical remote) during a burst: held while the
    // own call is unreplied, applied by the reconcile at its reply.
    function test_genuine_push_during_own_call_applies_at_the_reply() {
        state.notifyVolume(-30);
        push({ VolumeDb: -35 });
        compare(state.volumeDb, -30, "held while our call is unreplied");
        tryCompare(state, "volumeDb", -35);
        compare(state.ownVolumeCallsPending, 0);
    }

    // Owner requirement: a reply that never arrives must not leave pushes
    // ignored forever. beginOwnVolumeCall() alone is such a call (the fake
    // daemon always replies, so this is the only way to get one).
    function test_reply_that_never_arrives_is_reset_by_the_watchdog() {
        state.ownVolumeWatchdogMs = 300;
        const epoch = state.beginOwnVolumeCall();
        push({ VolumeDb: -33 });
        compare(state.volumeDb, -25, "held while the call looks in flight");
        tryCompare(state, "ownVolumeCallsPending", 0, 600);
        compare(state.volumeDb, -33, "reconciled to the daemon's value");
        push({ VolumeDb: -31 });
        compare(state.volumeDb, -31, "pushes are followed again");
        verify(!state.endOwnVolumeCall(epoch));
        compare(state.ownVolumeCallsPending, 0, "a late reply can't go below 0");
    }

    function test_late_reply_does_not_lower_a_newer_burst() {
        const epochA = state.beginOwnVolumeCall();
        state.resetOwnVolumeCalls("test");
        state.beginOwnVolumeCall();
        verify(!state.endOwnVolumeCall(epochA));
        compare(state.ownVolumeCallsPending, 1);
        state.resetOwnVolumeCalls("test cleanup");
    }

    function test_daemon_name_change_resets_the_count() {
        state.beginOwnVolumeCall();
        push({ VolumeDb: -37 });
        compare(state.volumeDb, -25);
        state.daemonWatcher.registeredChanged();
        compare(state.ownVolumeCallsPending, 0);
        compare(state.volumeDb, -37);
    }
}
