// Paces wheel notches into evenly spaced volume steps.
//
// Not a drop-based limiter ("ignore a notch less than N ms after the
// last"): a free-spinning wheel delivers notches on a ~7.5 ms grid, so a
// minimum gap lands between grid slots and the step rate jumps between
// ~44 and ~22 steps/s whatever the constant.
//
// Here the first notch after a quiet period steps at once (no added
// latency for ordinary scrolling), then a Timer spaces further steps
// exactly `intervalMs` apart. While notches keep arriving faster than
// that, at most one waits (the latest direction wins, so a reversal takes
// effect on the next tick); the rest are dropped, never queued, so a hard
// spin cannot build a backlog (a queue froze the UI).
//
// One instance per wheel surface (flyout slider in VolumeBlock.qml, panel
// icon in CompactRepresentation.qml); both bind intervalMs to
// VolumeSettings.wheelStepMinIntervalMs.
import QtQuick

QtObject {
    id: root

    required property int intervalMs

    // Emitted once per paced step; the owner calls its stepVolume path.
    signal step(int direction)

    // 0 = nothing waiting, else +1/-1.
    property int pending: 0

    function notch(direction) {
        if (root.pacer.running) {
            root.pending = direction;
            return;
        }
        root.step(direction);
        root.pacer.start();
    }

    // Named property, not a bare child - QtObject has no default property.
    readonly property Timer pacer: Timer {
        interval: root.intervalMs
        repeat: false
        onTriggered: {
            if (root.pending === 0) return;   // quiet: the next notch steps at once
            const direction = root.pending;
            root.pending = 0;
            root.step(direction);
            root.pacer.start();
        }
    }
}
