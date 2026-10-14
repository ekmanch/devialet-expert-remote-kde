// QtTest for DaemonAutostart.nextPrefix(), run by scripts/test-qml.sh.
// Every never-seen executable-engine command string permanently grows
// every executable DataSource's `data` map in plasmashell, so the
// systemctl commands must come from a fixed set (docs/DESIGN.md §5):
// the DEVIALET_SYSTEMD_TICK prefix wraps at tickSlots. nextPrefix() only
// builds the string; nothing here runs systemctl.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "DaemonAutostart"

    DaemonAutostart {
        id: autostart
    }

    function init() {
        autostart.tick = 0;
    }

    // Two commands issued back to back must differ, or the engine would
    // collapse the second into the first while it is still running.
    function test_consecutive_prefixes_differ() {
        const a = autostart.nextPrefix();
        const b = autostart.nextPrefix();
        verify(a !== b, "consecutive prefixes: " + a + " / " + b);
    }

    function test_prefix_wraps_at_tick_slots() {
        const first = autostart.nextPrefix();
        for (let i = 1; i < autostart.tickSlots; i++)
            autostart.nextPrefix();
        compare(autostart.nextPrefix(), first);
    }

    // The regression itself: a long session stays within tickSlots prefixes.
    function test_long_session_uses_a_fixed_set_of_prefixes() {
        const seen = {};
        let count = 0;
        for (let i = 0; i < 20000; i++) {
            const p = autostart.nextPrefix();
            if (!(p in seen)) { seen[p] = true; count++; }
        }
        compare(count, autostart.tickSlots);
    }
}
