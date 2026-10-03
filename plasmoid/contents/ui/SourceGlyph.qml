// Phase 17.7.0 - the painted source glyphs from the v2 flyout mockup
// (`const G = {...}`, flyout mockup v2 :630-636), replacing the text
// characters (◉ ◫ ◍ ◈ ◐ ◇) that Theme.sourceGlyph() used to return.
//
// Drawn on the mockup's own 20-unit grid and scaled to `size`, strokes
// included (SVG viewBox scaling): 1.6-unit outline strokes, 1.1 for Roon's
// four inner lines, round caps and joins (`.g .s`, :128-129). One flat
// `color` for strokes and fills - the dark theme's copper. The light
// theme's gold gradient + drop shadow (17.21.0) uses this item as an alpha
// mask source for GradientMask (Phase 17.0.2), so it deliberately has no
// background of its own and paints nothing outside its glyph.
//
// Name matching moved here unchanged from Theme.sourceGlyph(): keyed on
// the name the amp broadcasts (docs/devialet_source_mapping.md),
// case-insensitive keyword match so "Optical 2" or a renamed slot still
// resolves, "airplay" tested before "air", unknown or empty names fall
// back to optical (the glyph the closed row showed before any source was
// known).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: glyph

    property string sourceName: ""
    property real size: 20
    property color color: "black"

    readonly property string kind: glyph.kindFor(glyph.sourceName)
    readonly property real u: glyph.size / 20

    function kindFor(name) {
        const n = String(name || "").toLowerCase();
        if (n.indexOf("optical") >= 0) return "optical";
        if (n.indexOf("upnp") >= 0) return "upnp";
        if (n.indexOf("roon") >= 0) return "roon";
        if (n.indexOf("airplay") >= 0) return "airplay";
        if (n.indexOf("spotify") >= 0) return "spotify";
        if (n.indexOf("air") >= 0) return "air";
        return "optical";
    }

    implicitWidth: glyph.size
    implicitHeight: glyph.size

    // optical: ring r7.2 + filled centre r3
    Shape {
        anchors.fill: parent
        visible: glyph.kind === "optical"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathAngleArc {
                centerX: 10 * glyph.u; centerY: 10 * glyph.u
                radiusX: 7.2 * glyph.u; radiusY: 7.2 * glyph.u
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: glyph.color
            PathAngleArc {
                centerX: 10 * glyph.u; centerY: 10 * glyph.u
                radiusX: 3 * glyph.u; radiusY: 3 * glyph.u
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // upnp: rounded square 3,3 14x14 rx1.8 + centre line
    Shape {
        anchors.fill: parent
        visible: glyph.kind === "upnp"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathRectangle {
                x: 3 * glyph.u; y: 3 * glyph.u
                width: 14 * glyph.u; height: 14 * glyph.u
                radius: 1.8 * glyph.u
            }
        }
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 10 * glyph.u; startY: 3 * glyph.u
            PathLine { x: 10 * glyph.u; y: 17 * glyph.u }
        }
    }

    // roon: ring r7.2 + four vertical chords at stroke 1.1
    Shape {
        anchors.fill: parent
        visible: glyph.kind === "roon"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathAngleArc {
                centerX: 10 * glyph.u; centerY: 10 * glyph.u
                radiusX: 7.2 * glyph.u; radiusY: 7.2 * glyph.u
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.1 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 6.4 * glyph.u; startY: 5.08 * glyph.u
            PathLine { x: 6.4 * glyph.u; y: 14.92 * glyph.u }
            PathMove { x: 8.8 * glyph.u; y: 4.02 * glyph.u }
            PathLine { x: 8.8 * glyph.u; y: 15.98 * glyph.u }
            PathMove { x: 11.2 * glyph.u; y: 4.02 * glyph.u }
            PathLine { x: 11.2 * glyph.u; y: 15.98 * glyph.u }
            PathMove { x: 13.6 * glyph.u; y: 5.08 * glyph.u }
            PathLine { x: 13.6 * glyph.u; y: 14.92 * glyph.u }
        }
    }

    // airplay: outline diamond + filled inner diamond
    Shape {
        anchors.fill: parent
        visible: glyph.kind === "airplay"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 10 * glyph.u; startY: 2.6 * glyph.u
            PathLine { x: 17.4 * glyph.u; y: 10 * glyph.u }
            PathLine { x: 10 * glyph.u; y: 17.4 * glyph.u }
            PathLine { x: 2.6 * glyph.u; y: 10 * glyph.u }
            PathLine { x: 10 * glyph.u; y: 2.6 * glyph.u }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: glyph.color
            startX: 10 * glyph.u; startY: 6.6 * glyph.u
            PathLine { x: 13.4 * glyph.u; y: 10 * glyph.u }
            PathLine { x: 10 * glyph.u; y: 13.4 * glyph.u }
            PathLine { x: 6.6 * glyph.u; y: 10 * glyph.u }
            PathLine { x: 10 * glyph.u; y: 6.6 * glyph.u }
        }
    }

    // spotify: ring r7.2 + filled left half-disc
    // (M10 2.8 A7.2 7.2 0 0 0 10 17.2 Z - sweep-flag 0 = counterclockwise)
    Shape {
        anchors.fill: parent
        visible: glyph.kind === "spotify"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathAngleArc {
                centerX: 10 * glyph.u; centerY: 10 * glyph.u
                radiusX: 7.2 * glyph.u; radiusY: 7.2 * glyph.u
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: glyph.color
            startX: 10 * glyph.u; startY: 2.8 * glyph.u
            PathArc {
                x: 10 * glyph.u; y: 17.2 * glyph.u
                radiusX: 7.2 * glyph.u; radiusY: 7.2 * glyph.u
                direction: PathArc.Counterclockwise
            }
            PathLine { x: 10 * glyph.u; y: 2.8 * glyph.u }
        }
    }

    // air: outline diamond
    Shape {
        anchors.fill: parent
        visible: glyph.kind === "air"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: glyph.color
            strokeWidth: 1.6 * glyph.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 10 * glyph.u; startY: 2.6 * glyph.u
            PathLine { x: 17.4 * glyph.u; y: 10 * glyph.u }
            PathLine { x: 10 * glyph.u; y: 17.4 * glyph.u }
            PathLine { x: 2.6 * glyph.u; y: 10 * glyph.u }
            PathLine { x: 10 * glyph.u; y: 2.6 * glyph.u }
        }
    }
}
