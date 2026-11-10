// QtTest for the panel icon (Phase 19, docs/DESIGN.md §8), run by
// scripts/test-qml.sh. Geometry and state only (offscreen paints Shapes
// and effects blank): the five states, which parts each state shows, the
// number's fixed reserved width, and the vertical-panel rule.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

// The icon sits beside the TestCase, not inside it: a TestCase is an
// invisible Item, so every child of it reports `visible: false`.
Item {
    id: root
    width: 300
    height: 80

    PanelIcon {
        id: icon
        glyphSize: 20
        floorDb: -45
        ceilingDb: -10
    }

    TestCase {
        id: tc
        name: "PanelIcon"
        when: windowShown

        function init() {
            icon.style = "dial";
            icon.showNumber = true;
            icon.vertical = false;
            icon.hasAmp = true;
            icon.powerState = "On";
            icon.muted = false;
            icon.volumeDb = -22;
            icon.fraction = 23 / 35;
            icon.floorDb = -45;
            icon.ceilingDb = -10;
        }

        function part(name) { return findChild(icon, name); }

        function test_state_data() {
            return [
                { tag: "normal", hasAmp: true, power: "On", muted: false, state: "normal" },
                { tag: "muted", hasAmp: true, power: "On", muted: true, state: "muted" },
                { tag: "off", hasAmp: true, power: "Off", muted: false, state: "off" },
                // Mute is not shown for an amp that is off or booting.
                { tag: "off, muted flag set", hasAmp: true, power: "Off", muted: true, state: "off" },
                { tag: "booting", hasAmp: true, power: "Booting", muted: false, state: "booting" },
                { tag: "booting, muted flag set", hasAmp: true, power: "Booting", muted: true, state: "booting" },
                { tag: "no amp", hasAmp: false, power: "Off", muted: false, state: "none" },
                // No amp wins over a stale PowerState.
                { tag: "no amp, stale On", hasAmp: false, power: "On", muted: true, state: "none" }
            ];
        }
        function test_state(data) {
            icon.hasAmp = data.hasAmp;
            icon.powerState = data.power;
            icon.muted = data.muted;
            compare(icon.glyphState, data.state);
        }

        // The level and the number only show while the volume is known.
        function test_level_and_number_follow_volume_known_data() {
            return [
                { tag: "normal", hasAmp: true, power: "On", known: true },
                { tag: "off", hasAmp: true, power: "Off", known: false },
                { tag: "booting", hasAmp: true, power: "Booting", known: false },
                { tag: "no amp", hasAmp: false, power: "Off", known: false }
            ];
        }
        function test_level_and_number_follow_volume_known(data) {
            icon.hasAmp = data.hasAmp;
            icon.powerState = data.power;
            compare(icon.volumeKnown, data.known);
            compare(part("number").text, data.known ? "−22" : "—");
            compare(part("unit").visible, data.known);
            icon.style = "dial";
            compare(part("dialLevel").visible, data.known);
            icon.style = "level";
            compare(part("levelFillPartial").visible, data.known);
        }

        function test_on_without_a_volume_yet_shows_the_dash() {
            icon.volumeDb = undefined;
            compare(icon.glyphState, "normal");
            verify(!icon.volumeKnown);
            compare(part("number").text, "—");
        }

        function test_dial_parts() {
            icon.style = "dial";
            verify(part("dialTrack").visible);
            verify(part("dialHub").visible);
            verify(!part("levelRing").visible);
            verify(!part("dashedRing").visible);
            icon.powerState = "Off";
            verify(part("dialTrack").visible);
            verify(part("dialHub").visible);
            verify(!part("dialLevel").visible);
            fuzzyCompare(part("body").opacity, 0.35, 1e-9);
        }

        function test_level_parts() {
            icon.style = "level";
            verify(part("levelRing").visible);
            verify(!part("dialTrack").visible);
            verify(!part("dialHub").visible);
            // Floor: an empty ring. Ceiling: the whole disc.
            icon.fraction = 0;
            verify(!part("levelFillPartial").visible);
            verify(!part("levelFillFull").visible);
            icon.fraction = 1;
            verify(!part("levelFillPartial").visible);
            verify(part("levelFillFull").visible);
        }

        // No amp is the same dashed ring for both styles.
        function test_no_amp_is_the_dashed_ring_for_both_styles() {
            icon.hasAmp = false;
            for (const style of ["dial", "level"]) {
                icon.style = style;
                verify(part("dashedRing").visible);
                verify(!part("dialTrack").visible);
                verify(!part("dialHub").visible);
                verify(!part("levelRing").visible);
            }
        }

        function test_muted_slash_and_cutout() {
            verify(!part("slash").visible);
            verify(!part("mutedCutout").active);
            verify(part("body").visible);
            icon.muted = true;
            verify(part("slash").visible);
            verify(part("mutedCutout").active);
            // Painted through the cut-out instead.
            verify(!part("body").visible);
            fuzzyCompare(part("volumeNumber").opacity, 0.4, 1e-9);
            icon.muted = false;
            verify(!part("mutedCutout").active);
            verify(part("body").visible);
            fuzzyCompare(part("volumeNumber").opacity, 1.0, 1e-9);
        }

        function test_booting_without_animation_is_steady() {
            icon.powerState = "Booting";
            icon.animate = false;
            fuzzyCompare(part("body").opacity, 0.6, 1e-9);
            icon.animate = true;
        }

        // The reserved width: nothing beside the icon moves when the volume
        // or the state changes.
        function test_width_is_fixed_across_volumes_and_states() {
            const width = icon.implicitWidth;
            verify(width > icon.glyphSize);
            for (const db of [-45, -22.5, -10, -9, 0]) {
                icon.volumeDb = db;
                compare(icon.implicitWidth, width);
            }
            icon.muted = true;
            compare(icon.implicitWidth, width);
            icon.powerState = "Off";
            compare(icon.implicitWidth, width);
            icon.powerState = "Booting";
            compare(icon.implicitWidth, width);
            icon.hasAmp = false;
            compare(icon.implicitWidth, width);
            icon.style = "level";
            compare(icon.implicitWidth, width);
        }

        function test_reserve_fits_the_wider_range_end() {
            compare(icon.reserveChars, 3);
            const width = icon.implicitWidth;
            icon.volumeDb = -45;
            verify(part("number").implicitWidth + part("unit").implicitWidth < part("volumeNumber").implicitWidth + 1);
            icon.floorDb = -9;
            icon.ceilingDb = 0;
            compare(icon.reserveChars, 2);
            verify(icon.implicitWidth < width);
            icon.floorDb = -96;
            compare(icon.reserveChars, 3);
            compare(icon.implicitWidth, width);
        }

        function test_number_off_leaves_the_glyph_alone() {
            icon.showNumber = false;
            verify(!icon.numberShown);
            verify(!part("volumeNumber").visible);
            compare(icon.implicitWidth, icon.glyphSize);
            compare(icon.implicitHeight, icon.glyphSize);
        }

        // Always hidden on a vertical panel, whatever the setting.
        function test_vertical_panel_never_shows_the_number() {
            icon.vertical = true;
            icon.showNumber = true;
            verify(!icon.numberShown);
            verify(!part("volumeNumber").visible);
            compare(icon.implicitWidth, icon.glyphSize);
        }

        function test_number_format_data() {
            return [
                { tag: "-22", db: -22, text: "−22" },
                { tag: "-22.4", db: -22.4, text: "−22" },
                { tag: "-9", db: -9, text: "−9" },
                { tag: "0", db: 0, text: "0" },
                { tag: "-0.4 rounds to 0", db: -0.4, text: "0" },
                { tag: "-96", db: -96, text: "−96" }
            ];
        }
        function test_number_format(data) {
            compare(part("volumeNumber").format(data.db), data.text);
        }

        function test_scales_with_the_glyph() {
            icon.glyphSize = 20;
            compare(icon.gap, 6);
            compare(part("volumeNumber").fontPixelSize, 14);
            compare(part("glyph").width, 20);
            icon.glyphSize = 32;
            compare(part("glyph").width, 32);
            compare(icon.implicitHeight, 32);
            icon.glyphSize = 20;
        }
    }
}
