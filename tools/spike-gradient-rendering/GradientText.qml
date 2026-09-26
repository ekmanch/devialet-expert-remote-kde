// Spike: gradient-filled text with an optional soft glow (the light theme's
// readout digits "#dca136 -> #f3cf7c" + text-shadow, and the ConfigDialog
// heading gradient "#a8710b -> #d99a1f -> #efc36a").
import QtQuick
import QtQuick.Controls

Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    property color stop0Color: "#dca136"
    property real stop1Pos: 0.5
    property color stop1Color: Qt.rgba((stop0Color.r + stop2Color.r) / 2, (stop0Color.g + stop2Color.g) / 2, (stop0Color.b + stop2Color.b) / 2, 1)
    property color stop2Color: "#f3cf7c"
    property bool glow: false
    property color glowColor: "#c79a2e"
    property real glowOpacity: 0.35
    property real glowBlur: 0.5
    property int glowBlurMax: 32
    property bool twoStage: true

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Label {
        id: label
        anchors.fill: parent
        visible: false
        color: "black"
        layer.enabled: true
    }

    GradientMask {
        anchors.fill: parent
        maskSource: label
        stop0Color: root.stop0Color
        stop1Color: root.stop1Color
        stop1Pos: root.stop1Pos
        stop2Color: root.stop2Color
        shadowEnabled: root.glow
        shadowColor: root.glowColor
        shadowOpacity: root.glowOpacity
        shadowBlur: root.glowBlur
        shadowBlurMax: root.glowBlurMax
        shadowVerticalOffset: 0
        twoStage: root.twoStage
    }
}
