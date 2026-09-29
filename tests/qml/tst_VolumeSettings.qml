// QtTest for VolumeSettings.chimeArguments() (2026-09-29), run by
// scripts/test-qml.sh. Guards the fix for the scroll stutter that grew the
// longer the owner scrolled: every never-seen executable-engine command
// name permanently grows every executable DataSource's `data` map in
// plasmashell (see chimeArguments()' comment), so the chime's command
// strings must come from a small fixed set. Loudness equivalence with the
// old (target, confirmed) arguments was checked against the real
// devialet-chime --dry-run over 1,111 combinations; here we pin the
// strings and the bound.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "VolumeSettings"

    VolumeSettings {
        id: settings
        floorDb: -50
        hardLimitDb: -20
        stepDb: 1
        startupVolumeDb: -40
        chimeEnabled: true
        chimeSourceMode: "follow"
        chimePinnedTheme: ""
        chimeSoundFile: ""
        chimePinnedThemePath: ""
        soundThemes: null
    }

    function test_arguments_carry_only_the_delta() {
        compare(settings.chimeArguments(-30, -31, 0), " --target-db 1.0 --confirmed-db 0.0 --tick 0");
        compare(settings.chimeArguments(-31, -30, 3), " --target-db -1.0 --confirmed-db 0.0 --tick 3");
        compare(settings.chimeArguments(-40, -40, 5), " --target-db 0.0 --confirmed-db 0.0 --tick 5");
    }

    function test_delta_rounds_to_half_db_and_clamps_to_the_binarys_range() {
        compare(settings.chimeArguments(-30.3, -31, 0), " --target-db 0.5 --confirmed-db 0.0 --tick 0");
        compare(settings.chimeArguments(-20, -50, 0), " --target-db 20.0 --confirmed-db 0.0 --tick 0");
        compare(settings.chimeArguments(-50, -20, 0), " --target-db -20.0 --confirmed-db 0.0 --tick 0");
    }

    function test_tick_wraps_at_chime_slots() {
        compare(settings.chimeSlots, 16);
        compare(settings.chimeArguments(-30, -31, 16), settings.chimeArguments(-30, -31, 0));
        compare(settings.chimeArguments(-30, -31, 1234567), settings.chimeArguments(-30, -31, 1234567 % 16));
    }

    // The regression itself: a long session of back-and-forth scrolling
    // (every target between floor and ceiling against a lagging confirmed
    // value, far more ticks than names) stays within 81 deltas x 16 slots.
    function test_long_session_uses_a_bounded_set_of_command_strings() {
        const seen = {};
        let count = 0;
        for (let tick = 0; tick < 20000; tick++) {
            const target = -50 + (tick * 7) % 31;
            const confirmed = target - ((tick * 3) % 9) + 4;
            const args = settings.chimeArguments(target, confirmed, tick);
            if (!(args in seen)) { seen[args] = true; count++; }
        }
        verify(count <= 81 * 16, "distinct command strings: " + count);
    }
}
