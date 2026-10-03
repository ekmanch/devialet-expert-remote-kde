// QtTest for WheelStepPacer.qml (2026-09-29), run by scripts/test-qml.sh.
// Guards the two properties the owner tested live: a hard spin never builds
// a backlog (at most one notch waits), and while notches arrive faster than
// intervalMs the steps come out evenly spaced - the drop-based limiter it
// replaced alternated between two or more grid multiples (22.5 / 30 / 37.5
// ms on the owner's ~7.5 ms notch grid), which felt uneven.

import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: tc
    name: "WheelStepPacer"

    readonly property int intervalMs: 20

    Component {
        id: pacerComponent
        WheelStepPacer { intervalMs: tc.intervalMs }
    }

    property var pacer: null
    property var steps: []      // {direction, at}

    function recordStep(direction) {
        steps.push({ direction: direction, at: Date.now() });
    }

    // Feeds one notch per tick with the gaps measured on the owner's
    // free-spinning wheel (19:31-19:32 journal, before any limit: mostly
    // 7-8 ms, with skipped slots showing as 15 ms). The skipped slots are
    // what made the drop limiter's steps alternate between 22 and 30 ms.
    readonly property var feedGaps: [7, 8, 15, 7, 8, 7, 15, 8]
    Timer {
        id: feeder
        interval: 7
        repeat: false
        property int direction: 1
        property int index: 0
        property bool feeding: false
        onTriggered: {
            if (!feeding) return;
            tc.pacer.notch(direction);
            index = (index + 1) % tc.feedGaps.length;
            interval = tc.feedGaps[index];
            start();
        }
        function begin() { feeding = true; index = 0; interval = tc.feedGaps[0]; start(); }
        function end() { feeding = false; stop(); }
    }

    function init() {
        steps = [];
        pacer = pacerComponent.createObject(tc);
        pacer.step.connect(recordStep);
    }

    function cleanup() {
        feeder.end();
        pacer.destroy();
        pacer = null;
    }

    function test_first_notch_steps_at_once() {
        pacer.notch(1);
        compare(steps.length, 1, "no added latency for an ordinary notch");
        compare(steps[0].direction, 1);
    }

    function test_hard_spin_keeps_at_most_one_waiting() {
        for (let i = 0; i < 50; i++) pacer.notch(-1);
        compare(steps.length, 1);
        wait(intervalMs * 5);
        compare(steps.length, 2, "one waiting notch stepped, the other 48 dropped - no backlog");
        compare(steps[1].direction, -1);
    }

    function test_latest_direction_wins() {
        pacer.notch(1);
        pacer.notch(1);
        pacer.notch(-1);
        tryCompare(steps, "length", 2);
        compare(steps[1].direction, -1, "a reversal takes effect on the next tick");
    }

    function test_steady_feed_is_evenly_spaced() {
        feeder.direction = 1;
        feeder.begin();
        wait(420);
        feeder.end();
        verify(steps.length >= 15, "about 20 steps in 420 ms, got " + steps.length);
        let min = 1e9, max = 0;
        for (let i = 1; i < steps.length; i++) {
            const gap = steps[i].at - steps[i - 1].at;
            min = Math.min(min, gap);
            max = Math.max(max, gap);
        }
        // Timer jitter only; the drop limiter on this feed gives 22-23 and 30.
        verify(min >= intervalMs - 2, "no step closer than the interval, min " + min);
        verify(max <= intervalMs + 5, "evenly spaced, max " + max);
        const count = steps.length;
        wait(intervalMs * 4);
        verify(steps.length <= count + 1, "stops within one step after the wheel stops");
    }
}
