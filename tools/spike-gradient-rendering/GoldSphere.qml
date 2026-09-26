// Spike: the light theme's gold sphere (thumb, status dots):
// radial-gradient(circle at 32% 28%, #fcecc0 0%, #f0a623 38%, #a8710b 100%)
// + a warm drop shadow, and an optional translucent halo ring (the thumb's
// "0 0 0 3px rgba(240,166,35,0.14)").
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: root

    property real diameter: 12
    property bool shadowEnabled: true
    property color shadowColor: "#a06e0a"
    property real shadowOpacity: 0.35
    property real shadowBlur: 0.3
    property int shadowBlurMax: 16
    property real shadowVerticalOffset: 2
    property real haloWidth: 0
    property color haloColor: Qt.rgba(240 / 255, 166 / 255, 35 / 255, 0.14)

    implicitWidth: diameter
    implicitHeight: diameter

    Rectangle {
        visible: root.haloWidth > 0
        anchors.centerIn: parent
        width: root.diameter + 2 * root.haloWidth
        height: width
        radius: width / 2
        color: root.haloColor
    }

    Shape {
        id: sphere
        anchors.fill: parent
        visible: false
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.diameter * 0.32
                centerY: root.diameter * 0.28
                focalX: centerX
                focalY: centerY
                centerRadius: Math.hypot(root.diameter * 0.68, root.diameter * 0.72)
                GradientStop { position: 0.0; color: "#fcecc0" }
                GradientStop { position: 0.38; color: "#f0a623" }
                GradientStop { position: 1.0; color: "#a8710b" }
            }
            PathAngleArc {
                centerX: root.diameter / 2
                centerY: root.diameter / 2
                radiusX: root.diameter / 2
                radiusY: root.diameter / 2
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    MultiEffect {
        anchors.fill: sphere
        source: sphere
        shadowEnabled: root.shadowEnabled
        shadowColor: root.shadowColor
        shadowOpacity: root.shadowOpacity
        shadowBlur: root.shadowBlur
        blurMax: root.shadowBlurMax
        shadowVerticalOffset: root.shadowVerticalOffset
        autoPaddingEnabled: true
    }
}
