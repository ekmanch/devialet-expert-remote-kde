// The panel icon: PanelGlyph plus, on a horizontal panel with the setting
// on, the volume number (docs/DESIGN.md §8; tray icon mockup v7 widget()
// :339-345). Derives the glyph's state from the amp's, and sizes the gap
// and the number from the glyph (the mockup's 20 px glyph, 6 px gap, 14 px
// number). No Plasmoid or Kirigami import: CompactRepresentation.qml binds
// everything in, so tests/qml/tst_PanelIcon.qml can drive it directly.

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    // "dial" or "level" (kcfg panelIconStyle).
    property string style: "dial"
    // kcfg panelIconShowVolume.
    property bool showNumber: true
    // A vertical panel never shows the number, whatever the setting.
    property bool vertical: false

    property bool hasAmp: false
    // The daemon's PowerState: "Off", "Booting" or "On".
    property string powerState: "Off"
    property bool muted: false
    // PendingAmpState.volumeDb: a number, or undefined before the first
    // value.
    property var volumeDb: undefined
    // VolumeSettings.fractionFor(volumeDb).
    property real fraction: 0
    // The volume range, for the number's reserved width.
    property real floorDb: -50
    property real ceilingDb: -10

    property color color: "black"
    property real glyphSize: 20
    property bool animate: true

    // The mockup's five states.
    readonly property string glyphState: !root.hasAmp ? "none"
        : root.powerState === "Booting" ? "booting"
        : root.powerState !== "On" ? "off"
        : root.muted ? "muted" : "normal"
    // The level and the number show only while the volume is known.
    readonly property bool volumeKnown: (root.glyphState === "normal" || root.glyphState === "muted")
        && typeof root.volumeDb === "number"
    readonly property bool numberShown: root.showNumber && !root.vertical

    readonly property int gap: Math.round(root.glyphSize * 0.3)
    // The wider of the two range ends, as the number prints them.
    readonly property int reserveChars: Math.max(number.format(root.floorDb).length,
                                                 number.format(root.ceilingDb).length)

    implicitWidth: root.glyphSize + (root.numberShown ? root.gap + number.implicitWidth : 0)
    implicitHeight: root.glyphSize

    PanelGlyph {
        id: glyph
        objectName: "glyph"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        size: root.glyphSize
        style: root.style
        glyphState: root.glyphState
        fraction: root.volumeKnown ? root.fraction : 0
        color: root.color
        animate: root.animate
    }

    PanelVolumeNumber {
        id: number
        objectName: "volumeNumber"
        anchors.left: glyph.right
        anchors.leftMargin: root.gap
        anchors.verticalCenter: parent.verticalCenter
        visible: root.numberShown
        known: root.volumeKnown
        volumeDb: root.volumeKnown ? root.volumeDb : 0
        muted: root.glyphState === "muted"
        color: root.color
        fontPixelSize: Math.round(root.glyphSize * 0.7)
        reserveChars: root.reserveChars
    }
}
