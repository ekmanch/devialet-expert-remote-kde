// Paces wheel notches into evenly spaced volume steps (2026-09-29).
//
// Replaces a drop-based limiter ("ignore a notch less than N ms after the
// last accepted one"). Measured on the owner's free-spinning wheel: notches
// arrive on a ~7.5 ms grid (gaps of 7-8, 15, 22, 30, 37, 45 ms before any
// limit existed), so dropping to a 20 ms minimum really accepted the first
// notch at 22.5, 30, 37.5 or 45 ms - the step rate jumped between ~44 and
// ~22 steps/s while spinning, which felt uneven. Changing the constant can't
// fix that; any value falls between grid slots.
//
// Here the first notch after a quiet period steps at once (no added
// latency for ordinary scrolling), then a Timer spaces further steps
// exactly `intervalMs` apart. While notches keep arriving faster than
// that, at most one waits (the latest direction wins, so a reversal takes
// effect on the next tick); the rest are dropped, never queued, so a hard
// spin cannot build a backlog - the freeze the original limiter fixed.
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
