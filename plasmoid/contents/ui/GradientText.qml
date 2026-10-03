// Promoted from tools/spike-gradient-rendering/ (Phase 17.0.2) in Phase
// 17.20.0: gradient-filled text with an optional soft glow, for the light
// theme's volume readout and "DEVIALET" wordmark (flyout mockup v22
// :109-120).
//
// A hidden Label is the alpha mask; GradientMask.qml paints a horizontal
// gradient through it. Size this item like the text it replaces (the
// gradient spans this item's width, so give it the text's own width when
// the sweep should end at the last glyph). Create it inside a Loader that
// is active only in the light theme: its layers must exist from the start
// (toggling `layer.enabled` at runtime stopped masking after a dark ->
// light flip, see CardShadow.qml).
import QtQuick
import QtQuick.Controls

Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    required property color startColor
    required property color endColor
    property bool glow: false
    property color glowColor: "#c79a2e"
    property real glowOpacity: 0.35
    property real glowBlur: 0.9
    property int glowBlurMax: 32

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Label {
        id: label
        anchors.fill: parent
        visible: false
        color: "black"
        wrapMode: Text.NoWrap
        layer.enabled: true
    }

    GradientMask {
        anchors.fill: parent
        maskSource: label
        stop0Color: root.startColor
        stop1Pos: 0.5
        stop1Color: Qt.rgba((root.startColor.r + root.endColor.r) / 2, (root.startColor.g + root.endColor.g) / 2, (root.startColor.b + root.endColor.b) / 2, 1)
        stop2Color: root.endColor
        shadowEnabled: root.glow
        shadowColor: root.glowColor
        shadowOpacity: root.glowOpacity
        shadowBlur: root.glowBlur
        shadowBlurMax: root.glowBlurMax
        shadowVerticalOffset: 0
    }
}
