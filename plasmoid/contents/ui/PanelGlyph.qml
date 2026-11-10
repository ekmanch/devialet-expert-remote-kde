// The panel icon's glyph (docs/DESIGN.md §8; tray icon mockup v7,
// "Geometry" :232-260 and the dial()/level()/dashed()/slash() builders
// :285-332). Two styles on a 24-unit grid, five states, every stroke and
// fill in the one `color` it is handed: Kirigami.Theme.textColor on the
// panel, the page's text or label colour on the settings page, which
// instantiates this same component for its segment glyphs and Preview.
//
//   style       "dial"  - 270 deg arc (r 8.5, stroke 2.2, round caps, gap at
//                         the bottom) as a 28 % track, the same arc at
//                         100 % from 135 deg clockwise for `fraction`, hub
//                         r 1.7.
//               "level" - full ring (r 8.5, stroke 1.8) around a disc
//                         (r 6.6) cut by a horizontal chord at
//                         2 * r * fraction from the bottom. No hub.
//   glyphState  "normal"  - the level at 100 %.
//               "muted"   - level (and the dial's hub) at 28 %, a slash
//                           across.
//               "off"     - the empty outline at 35 %.
//               "booting" - the empty outline pulsing 0.9 <-> 0.25 over
//                           1.1 s; steady 0.6 when `animate` is false.
//               "none"    - a dashed ring, the same for both styles.
//
// The mute slash's halo is a cut-out, not a panel-coloured stroke: the
// panel's real colour cannot be known here (docs/DESIGN.md §8). The halo
// stroke is the inverted mask of a MultiEffect over `body`, built by the
// §6 effect rules: inside a Loader, layers on from creation, mask
// threshold 0.5 / spread 1.0.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// Root is a plain Item, as in Tick.qml: a Shape sizes itself from its
// path's bounds, the Item keeps the square slot.
Item {
    id: glyph

    property string style: "dial"
    property string glyphState: "normal"
    // 0..1 between the volume floor and ceiling. Only read in "normal"
    // and "muted".
    property real fraction: 0
    property color color: "black"
    property real size: 20
    // False for reduced motion: the host binds it to the desktop's
    // animation setting (this file stays free of Kirigami).
    property bool animate: true

    readonly property real u: glyph.size / 24
    readonly property bool isLevel: glyph.style === "level"
    readonly property bool volumeShown: glyph.glyphState === "normal" || glyph.glyphState === "muted"
    readonly property bool muted: glyph.glyphState === "muted"
    readonly property bool outlineOnly: glyph.glyphState === "off" || glyph.glyphState === "booting"
    readonly property bool noAmp: glyph.glyphState === "none"
    readonly property real clampedFraction: Math.min(1, Math.max(0, glyph.fraction))

    // Mockup opacities.
    readonly property real trackOpacity: 0.28
    readonly property real mutedOpacity: 0.28
    readonly property real offOpacity: 0.35
    readonly property real dashedOpacity: 0.75
    readonly property real reducedMotionOpacity: 0.6
    readonly property real levelOpacity: glyph.muted ? glyph.mutedOpacity : 1.0

    // Shared geometry, in grid units.
    readonly property real ringRadius: 8.5
    readonly property real dialStroke: 2.2
    readonly property real ringStroke: 1.8
    readonly property real hubRadius: 1.7
    readonly property real fillRadius: 6.6
    readonly property real slashFrom: 5.2
    readonly property real slashTo: 18.8

    // Level fill: the chord's height and half-width (mockup fillPath()).
    readonly property real chordY: 12 + glyph.fillRadius - 2 * glyph.fillRadius * glyph.clampedFraction
    readonly property real chordHalf: Math.sqrt(Math.max(0, glyph.fillRadius * glyph.fillRadius
                                                         - (glyph.chordY - 12) * (glyph.chordY - 12)))

    function tint(opacity) {
        return Qt.rgba(glyph.color.r, glyph.color.g, glyph.color.b, glyph.color.a * opacity);
    }

    implicitWidth: glyph.size
    implicitHeight: glyph.size

    // The booting pulse, CSS `pulse 1.1s ease-in-out infinite` between
    // 0.9 and 0.25. Runs only while booting, so an idle panel animates
    // nothing.
    property real pulse: 0.9
    SequentialAnimation {
        running: glyph.glyphState === "booting" && glyph.animate
        loops: Animation.Infinite
        NumberAnimation {
            target: glyph; property: "pulse"; from: 0.9; to: 0.25; duration: 550
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1]
        }
        NumberAnimation {
            target: glyph; property: "pulse"; from: 0.25; to: 0.9; duration: 550
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.42, 0, 0.58, 1, 1, 1]
        }
    }

    // Everything except the slash. Hidden while muted, when the Loader
    // below paints it through the halo cut-out instead.
    Item {
        id: body
        objectName: "body"
        anchors.fill: parent
        visible: !glyph.muted
        opacity: glyph.glyphState === "off" ? glyph.offOpacity
            : glyph.glyphState === "booting" ? (glyph.animate ? glyph.pulse : glyph.reducedMotionOpacity)
            : 1.0

        // ---- no amp: dashed ring. SVG `pathLength="48"
        // stroke-dasharray="3 3"` is eight 22.5 deg dashes; drawn as eight
        // arcs so it does not depend on a renderer's dash support. ----
        Shape {
            objectName: "dashedRing"
            anchors.fill: parent
            visible: glyph.noAmp
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: glyph.tint(glyph.dashedOpacity)
                strokeWidth: glyph.ringStroke * glyph.u
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 0; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 45; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 90; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 135; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 180; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 225; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 270; sweepAngle: 22.5 }
                PathAngleArc { centerX: 12 * glyph.u; centerY: 12 * glyph.u; radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u; startAngle: 315; sweepAngle: 22.5 }
            }
        }

        // ---- Dial: track. 28 % under a level; the whole outline at
        // 100 % when off or booting (the body's opacity dims it). ----
        Shape {
            objectName: "dialTrack"
            anchors.fill: parent
            visible: !glyph.isLevel && !glyph.noAmp
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: glyph.tint(glyph.outlineOnly ? 1.0 : glyph.trackOpacity)
                strokeWidth: glyph.dialStroke * glyph.u
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 12 * glyph.u; centerY: 12 * glyph.u
                    radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u
                    startAngle: 135; sweepAngle: 270
                }
            }
        }

        // ---- Dial: level, from 135 deg clockwise. At the floor the SVG's
        // zero-length dash still paints its round cap as a dot; the
        // minimum sweep keeps that. ----
        Shape {
            objectName: "dialLevel"
            anchors.fill: parent
            visible: !glyph.isLevel && glyph.volumeShown
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: glyph.tint(glyph.levelOpacity)
                strokeWidth: glyph.dialStroke * glyph.u
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 12 * glyph.u; centerY: 12 * glyph.u
                    radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u
                    startAngle: 135; sweepAngle: Math.max(0.01, 270 * glyph.clampedFraction)
                }
            }
        }

        // ---- Dial: hub. ----
        Shape {
            objectName: "dialHub"
            anchors.fill: parent
            visible: !glyph.isLevel && !glyph.noAmp
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: glyph.tint(glyph.outlineOnly ? 1.0 : glyph.levelOpacity)
                PathAngleArc {
                    centerX: 12 * glyph.u; centerY: 12 * glyph.u
                    radiusX: glyph.hubRadius * glyph.u; radiusY: glyph.hubRadius * glyph.u
                    startAngle: 0; sweepAngle: 360
                }
            }
        }

        // ---- Level: ring, always at 100 %. ----
        Shape {
            objectName: "levelRing"
            anchors.fill: parent
            visible: glyph.isLevel && !glyph.noAmp
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: glyph.color
                strokeWidth: glyph.ringStroke * glyph.u
                fillColor: "transparent"
                PathAngleArc {
                    centerX: 12 * glyph.u; centerY: 12 * glyph.u
                    radiusX: glyph.ringRadius * glyph.u; radiusY: glyph.ringRadius * glyph.u
                    startAngle: 0; sweepAngle: 360
                }
            }
        }

        // ---- Level: fill. Nothing at the floor (<= 0.001), the whole
        // disc at the ceiling (>= 0.999), a chord-cut segment between
        // (mockup fillPath()). ----
        Shape {
            objectName: "levelFillFull"
            anchors.fill: parent
            visible: glyph.isLevel && glyph.volumeShown && glyph.clampedFraction >= 0.999
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: glyph.tint(glyph.levelOpacity)
                PathAngleArc {
                    centerX: 12 * glyph.u; centerY: 12 * glyph.u
                    radiusX: glyph.fillRadius * glyph.u; radiusY: glyph.fillRadius * glyph.u
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        Shape {
            objectName: "levelFillPartial"
            anchors.fill: parent
            visible: glyph.isLevel && glyph.volumeShown
                && glyph.clampedFraction > 0.001 && glyph.clampedFraction < 0.999
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: glyph.tint(glyph.levelOpacity)
                startX: (12 - glyph.chordHalf) * glyph.u
                startY: glyph.chordY * glyph.u
                // SVG `A r r 0 <f > 0.5> 0`: sweep flag 0, through the
                // bottom of the disc.
                PathArc {
                    x: (12 + glyph.chordHalf) * glyph.u
                    y: glyph.chordY * glyph.u
                    radiusX: glyph.fillRadius * glyph.u
                    radiusY: glyph.fillRadius * glyph.u
                    useLargeArc: glyph.clampedFraction > 0.5
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: (12 - glyph.chordHalf) * glyph.u
                    y: glyph.chordY * glyph.u
                }
            }
        }
    }

    // ---- muted: the body through the slash's halo cut-out. ----
    Loader {
        objectName: "mutedCutout"
        anchors.fill: parent
        active: glyph.muted
        sourceComponent: Item {
            // The halo: the slash's line at stroke 5, round caps (mockup
            // slash()). Only its alpha is used.
            Shape {
                id: haloMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "black"
                    strokeWidth: 5 * glyph.u
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: glyph.slashFrom * glyph.u; startY: glyph.slashFrom * glyph.u
                    PathLine { x: glyph.slashTo * glyph.u; y: glyph.slashTo * glyph.u }
                }
            }

            MultiEffect {
                anchors.fill: parent
                source: body
                maskEnabled: true
                maskSource: haloMask
                maskInverted: true
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
    }

    // ---- muted: the slash itself, at 100 %. ----
    Shape {
        objectName: "slash"
        anchors.fill: parent
        visible: glyph.muted
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 2 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: glyph.slashFrom * glyph.u; startY: glyph.slashFrom * glyph.u
            PathLine { x: glyph.slashTo * glyph.u; y: glyph.slashTo * glyph.u }
        }
    }
}
