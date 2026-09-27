// QtTest geometry tests for the real SourceListOverlay.qml (Phase 17.1.1),
// run by scripts/test-qml.sh. Geometry only, no pixels: the offscreen
// platform the script uses renders effects blank (Phase 17 capture rule),
// but item positions and sizes are exact there.
//
// The overlay is parented to a stand-in source row placed where the real
// one sits since Phase 17.1.0 removed the scroll hint: 217 px of room above
// it (SourceListOverlay's spaceAbove = row top - gap 6 - margin 8), which
// is less than the six-source list needs (244 px), so the list scrolls.
// Guards the two 17.1.1 regressions measured on the harness:
//   - the selected source must be fully visible when the list opens, even
//     when it is the last row (the real amp's AIR slot, index 14);
//   - rows must be exactly as wide as the scroll viewport, so the scrollbar
//     never covers their right edge (where the selection tick sits).

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "SourceListOverlay"
    width: 300
    height: 330
    when: windowShown

    // The real amp's enabled sources (harness scenarios.SOURCE_TABLE).
    readonly property var sixSources: [
        { name: "Optical 1", index: 0, enabled: true, selected: false },
        { name: "UPnP", index: 1, enabled: true, selected: false },
        { name: "Roon Ready", index: 2, enabled: true, selected: false },
        { name: "AirPlay", index: 3, enabled: true, selected: false },
        { name: "Spotify", index: 4, enabled: true, selected: false },
        { name: "AIR", index: 14, enabled: true, selected: false }
    ]
    readonly property var threeSources: sixSources.slice(0, 3)

    Theme { id: testTheme }
    DarkPalette { id: testColors }
    TransparencySettings { id: testTransparency; enabled: false; percent: 100 }

    // Stand-in for SourceSelector's row: same 16 px side inset, 50 px tall,
    // top edge at 231 (the post-17.1.0 flyout: window 330, row at 231).
    Item {
        id: row
        x: 16
        y: 231
        width: 268
        height: 50
    }

    Component {
        id: overlayComponent
        SourceListOverlay {
            theme: testTheme
            colors: testColors
            transparencySettings: testTransparency
            enabledSources: tc.sixSources
            activeSourceIndex: 0
        }
    }

    property var overlay: null

    function findByName(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; ++i) {
            const hit = findByName(kids[i], name);
            if (hit) return hit;
        }
        return null;
    }

    function tickOf(rowItem, sourceIndex) {
        // Phase 17.8.0: the painted Tick, found by its objectName.
        return findByName(rowItem, "sourceOptionTick:" + sourceIndex);
    }

    function openWith(sources, activeIndex) {
        overlay = createTemporaryObject(overlayComponent, row, {
            enabledSources: sources,
            activeSourceIndex: activeIndex
        });
        verify(overlay, "overlay created");
        overlay.open();
        tryVerify(function () { return overlay.opened; }, 2000, "overlay opened");
        // Let the layouts and any open-time scroll settle.
        wait(50);
        return overlay.contentItem.contentItem;   // ScrollView's Flickable
    }

    function cleanup() {
        if (overlay) overlay.close();
        overlay = null;
    }

    function test_six_sources_scroll_in_the_post_17_1_0_space() {
        const flick = openWith(sixSources, 0);
        compare(overlay.height, 217, "capped to the room above the row");
        verify(flick.contentHeight > flick.height, "content taller than the viewport, so it scrolls");
    }

    function test_selected_source_is_fully_visible_on_open_data() {
        return sixSources.map(function (s) { return { tag: s.name, sourceIndex: s.index }; });
    }
    function test_selected_source_is_fully_visible_on_open(data) {
        const flick = openWith(sixSources, data.sourceIndex);
        const rowItem = findByName(overlay.contentItem, "sourceOption:" + data.sourceIndex);
        verify(rowItem, "selected row exists");
        const top = rowItem.mapToItem(flick, 0, 0).y;
        const bottom = top + rowItem.height;
        verify(top >= 0, "selected row top " + top + " inside the viewport");
        verify(bottom <= flick.height, "selected row bottom " + bottom + " inside the viewport (" + flick.height + ")");
        const tick = tickOf(rowItem, data.sourceIndex);
        verify(tick && tick.visible, "tick shown on the selected row");
        const tickRight = tick.mapToItem(flick, tick.width, 0).x;
        verify(tickRight <= flick.width, "tick right edge " + tickRight + " inside the viewport width " + flick.width);
    }

    function test_rows_fill_exactly_the_viewport_width_data() {
        return [
            { tag: "six sources, scrolling", sources: sixSources },
            { tag: "three sources, no scrollbar", sources: threeSources }
        ];
    }
    function test_rows_fill_exactly_the_viewport_width(data) {
        const flick = openWith(data.sources, data.sources[0].index);
        for (let i = 0; i < data.sources.length; ++i) {
            const rowItem = findByName(overlay.contentItem, "sourceOption:" + data.sources[i].index);
            verify(rowItem, "row " + data.sources[i].name);
            compare(rowItem.width, flick.width, "row " + data.sources[i].name + " width equals the viewport width");
        }
    }

    function test_short_list_opens_unscrolled() {
        const flick = openWith(threeSources, 2);
        verify(flick.contentHeight <= flick.height, "three sources fit without scrolling");
        compare(flick.contentY, 0, "no scroll when everything fits");
    }

    function test_first_source_selected_keeps_the_list_at_the_top() {
        const flick = openWith(sixSources, 0);
        compare(flick.contentY, 0, "already visible, so no scroll");
    }
}
