// Phase 17.24.0 - the brand mark in the settings page header: the app icon's
// ring + disk filling the tile (configDialog mockup v30 :236-255), in place
// of the small "◉" character. Dark: flat ring #654c3a over #262221, disk
// #e3a06a. Light: white tile with the card shadow, ring and disk in 145
// degree gold sweeps. Both themes paint the same Shapes; the palette's
// brand* tokens carry one flat colour per shape in dark.
//
// QtQuick.Shapes has no stroke gradient, so the ring is a gradient-filled
// disc with a second disc (brandRingInner) inset by the ring's 2.5 px.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../ui" as Ui

Rectangle {
    id: mark

    required property Ui.ColorPalette colors

    implicitWidth: 37
    implicitHeight: 37
    radius: 8
    color: mark.colors.surface
    border.width: 1
    border.color: mark.colors.copperDim

    Ui.CardShadow { colors: mark.colors; radius: mark.radius }

    // A disc of `diameter` filled with a CSS "145deg" linear gradient:
    // the gradient line runs through the centre along (sin, -cos) of the
    // angle, as long as the box's projection onto it.
    component SweepDisc: Shape {
        id: disc
        required property real diameter
        required property color startColor
        required property color midColor
        required property real midPos
        required property color endColor
        readonly property real dx: Math.sin(145 * Math.PI / 180)
        readonly property real dy: -Math.cos(145 * Math.PI / 180)
        readonly property real half: disc.diameter * (Math.abs(disc.dx) + Math.abs(disc.dy)) / 2

        anchors.centerIn: parent
        width: disc.diameter
        height: disc.diameter
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: disc.diameter / 2 - disc.dx * disc.half
                y1: disc.diameter / 2 - disc.dy * disc.half
                x2: disc.diameter / 2 + disc.dx * disc.half
                y2: disc.diameter / 2 + disc.dy * disc.half
                GradientStop { position: 0.0; color: disc.startColor }
                GradientStop { position: disc.midPos; color: disc.midColor }
                GradientStop { position: 1.0; color: disc.endColor }
            }
            PathAngleArc {
                centerX: disc.diameter / 2
                centerY: disc.diameter / 2
                radiusX: disc.diameter / 2
                radiusY: disc.diameter / 2
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    SweepDisc {
        diameter: 25
        startColor: mark.colors.brandRingStart
        midColor: mark.colors.brandRingMid
        midPos: 0.6
        endColor: mark.colors.brandRingEnd
    }
    SweepDisc {
        diameter: 20
        startColor: mark.colors.brandRingInner
        midColor: mark.colors.brandRingInner
        midPos: 0.5
        endColor: mark.colors.brandRingInner
    }
    SweepDisc {
        diameter: 15
        startColor: mark.colors.brandDiskStart
        midColor: mark.colors.brandDiskMid
        midPos: 0.55
        endColor: mark.colors.brandDiskEnd
    }
}
