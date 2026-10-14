// QtTest for ActionRow's dimming, run by scripts/test-qml.sh. Opacities
// multiply, so this checks what is actually painted (row x button), not
// each item's own `opacity`: mute dims itself while the amp is Off or
// Booting (known-gotchas #10), the whole row dims with no amp, and the two
// must not stack to 0.16. Power stays live while Off.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "ActionRow"
    when: windowShown
    width: 300
    height: 120

    Theme { id: testTheme }
    DarkPalette { id: testColors }
    TransparencySettings { id: testTransparency; enabled: false; percent: 100 }

    ActionRow {
        id: row
        width: 268
        theme: testTheme
        colors: testColors
        transparencySettings: testTransparency
        ampIp: "192.0.2.1"
        muted: false
        power: true
        powerState: "On"
    }

    function muteButton() { return findChild(row, "muteButton"); }
    function powerButton() { return findChild(row, "powerButton"); }
    function painted(item) { return row.opacity * item.opacity; }

    function setState(ampIp, powerState) {
        row.ampIp = ampIp;
        row.powerState = powerState;
        row.power = powerState === "On";
    }

    function test_on_everything_live() {
        setState("192.0.2.1", "On");
        verify(muteButton().enabled);
        verify(powerButton().enabled);
        fuzzyCompare(painted(muteButton()), 1.0, 1e-9);
        fuzzyCompare(painted(powerButton()), 1.0, 1e-9);
    }

    function test_off_mute_dimmed_power_live() {
        setState("192.0.2.1", "Off");
        verify(!muteButton().enabled);
        verify(powerButton().enabled);
        fuzzyCompare(painted(muteButton()), 0.4, 1e-9);
        fuzzyCompare(painted(powerButton()), 1.0, 1e-9);
    }

    function test_booting_mute_dimmed_power_inert() {
        setState("192.0.2.1", "Booting");
        verify(!muteButton().enabled);
        verify(!powerButton().enabled);
        fuzzyCompare(painted(muteButton()), 0.4, 1e-9);
    }

    // The regression: with no amp the row's 0.4 and mute's own 0.4 used to
    // stack, painting mute at 0.16 next to a 0.4 power button.
    function test_no_amp_mute_and_power_dim_alike() {
        setState("", "Off");
        verify(!muteButton().enabled);
        verify(!powerButton().enabled);
        fuzzyCompare(painted(muteButton()), 0.4, 1e-9);
        fuzzyCompare(painted(powerButton()), 0.4, 1e-9);
    }
}
