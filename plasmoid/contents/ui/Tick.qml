// Phase 17.8.0 - the painted selection tick from the v2 flyout mockup
// (`.tick`, flyout mockup v2 :452-453, used at :685 and :707): one stroked
// path `M3.8 9.4 L7.4 12.9 L14.2 5.4` on an 18-unit grid shown at 16 px,
// 2-unit round-capped, round-joined stroke, flat `color`. Replaces the 11 px
// "✓" text character in the amp and source lists. Like SourceGlyph.qml it
// paints nothing but itself, so the light theme (17.21.0) can use it as a
// GradientMask alpha source.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// Root is a plain Item: a Shape sets its own implicit size from its path's
// bounds (measured 14x13 px here), which would override the mockup's 16 px
// box; the Item keeps the 16x16 slot and the Shape fills it.
Item {
    id: tick

    property real size: 16
    property color color: "black"
    readonly property real u: tick.size / 18

    implicitWidth: tick.size
    implicitHeight: tick.size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: tick.color
            strokeWidth: 2 * tick.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 3.8 * tick.u; startY: 9.4 * tick.u
            PathLine { x: 7.4 * tick.u; y: 12.9 * tick.u }
            PathLine { x: 14.2 * tick.u; y: 5.4 * tick.u }
        }
    }
}
