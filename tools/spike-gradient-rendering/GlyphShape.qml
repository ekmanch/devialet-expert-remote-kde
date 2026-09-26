// Spike: two of the mockup's painted 20-unit source glyphs as Shapes, flat
// colour (the dark theme) or as an alpha source for GradientMask (light).
// Paths: flyout mockup v2 :630-636 (optical: circle r7.2 stroke 1.6 + filled
// circle r3; airplay: diamond stroke 1.6 + filled inner diamond).
import QtQuick
import QtQuick.Shapes

Shape {
    id: root
    property string kind: "optical"
    property real size: 20
    property color color: "#c17f4e"
    readonly property real u: size / 20
    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer

    // optical
    ShapePath {
        strokeColor: root.kind === "optical" ? root.color : "transparent"
        strokeWidth: 1.6 * root.u
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc { centerX: 10 * root.u; centerY: 10 * root.u; radiusX: 7.2 * root.u; radiusY: 7.2 * root.u; startAngle: 0; sweepAngle: 360 }
    }
    ShapePath {
        strokeWidth: -1
        fillColor: root.kind === "optical" ? root.color : "transparent"
        PathAngleArc { centerX: 10 * root.u; centerY: 10 * root.u; radiusX: 3 * root.u; radiusY: 3 * root.u; startAngle: 0; sweepAngle: 360 }
    }
    // airplay
    ShapePath {
        strokeColor: root.kind === "airplay" ? root.color : "transparent"
        strokeWidth: 1.6 * root.u
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        startX: 10 * root.u; startY: 2.6 * root.u
        PathLine { x: 17.4 * root.u; y: 10 * root.u }
        PathLine { x: 10 * root.u; y: 17.4 * root.u }
        PathLine { x: 2.6 * root.u; y: 10 * root.u }
        PathLine { x: 10 * root.u; y: 2.6 * root.u }
    }
    ShapePath {
        strokeWidth: -1
        fillColor: root.kind === "airplay" ? root.color : "transparent"
        startX: 10 * root.u; startY: 6.6 * root.u
        PathLine { x: 13.4 * root.u; y: 10 * root.u }
        PathLine { x: 10 * root.u; y: 13.4 * root.u }
        PathLine { x: 6.6 * root.u; y: 10 * root.u }
        PathLine { x: 10 * root.u; y: 6.6 * root.u }
    }
}
