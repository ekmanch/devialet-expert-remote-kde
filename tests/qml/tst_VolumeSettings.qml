// QtTest for VolumeSettings.chimeArguments() (2026-09-29), run by
// scripts/test-qml.sh. Guards the fix for the scroll stutter that grew the
// longer the owner scrolled: every never-seen executable-engine command
// name permanently grows every executable DataSource's `data` map in
// plasmashell (see chimeArguments()' comment), so the chime's command
// strings must come from a small fixed set: only `--tick k`, the binary
// reads the volumes from the daemon (crates/devialet-chime/src/daemon.rs).
// Here we pin the strings and the bound.

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

    function test_arguments_are_only_the_tick() {
        compare(settings.chimeArguments(0), " --tick 0");
        compare(settings.chimeArguments(5), " --tick 5");
        compare(settings.chimeArguments(15), " --tick 15");
    }

    function test_tick_wraps_at_chime_slots() {
        compare(settings.chimeSlots, 16);
        compare(settings.chimeArguments(16), " --tick 0");
        compare(settings.chimeArguments(1234567), " --tick " + (1234567 % 16));
    }

    // The regression itself: a long session stays within chimeSlots names.
    function test_long_session_uses_a_fixed_set_of_command_strings() {
        const seen = {};
        let count = 0;
        for (let tick = 0; tick < 20000; tick++) {
            const args = settings.chimeArguments(tick);
            if (!(args in seen)) { seen[args] = true; count++; }
        }
        compare(count, settings.chimeSlots);
    }
}
