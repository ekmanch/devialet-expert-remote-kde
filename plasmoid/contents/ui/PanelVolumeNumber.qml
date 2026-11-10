// The volume number beside the panel glyph (docs/DESIGN.md §8; tray icon
// mockup v7 `.dv-num` :102-104 and widget() :339-345): whole dB in the mono
// font with a small "dB" at 0.7 em and 60 %, or a dash while the volume is
// not known. Also the settings page's Preview number.
//
// `reserveChars` > 0 fixes the width at that many digits plus the unit
// (the mockup's RESERVE, :337), so nothing beside the number moves when
// its length changes; the text is left-aligned inside it. 0 sizes to the
// text (the Preview, which is right-aligned by its row instead).

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    // False: shows the dash (amp off, booting, or none).
    property bool known: false
    property real volumeDb: 0
    // Mockup `.dv-num.faded`.
    property bool muted: false
    property color color: "black"
    property int fontPixelSize: 14
    property int reserveChars: 0

    readonly property Theme theme: Theme {}

    // "−22" for -22.4: U+2212 and the rounded magnitude (mockup fmt(),
    // :336). The sign comes from the rounded value, so -0.4 is "0".
    function format(db) {
        const rounded = Math.round(db);
        return (rounded < 0 ? "−" : "") + Math.abs(rounded);
    }

    // `.u{margin-left:1px}`.
    readonly property int unitGap: 1
    readonly property real reservedWidth: Math.ceil(root.reserveChars * digit.advanceWidth + root.unitGap + unit.implicitWidth)
    readonly property real naturalWidth: number.implicitWidth + (root.known ? root.unitGap + unit.implicitWidth : 0)

    implicitWidth: root.reserveChars > 0 ? root.reservedWidth : Math.ceil(root.naturalWidth)
    implicitHeight: number.implicitHeight
    opacity: root.muted ? 0.4 : 1.0

    // One digit's advance; every digit and the minus sign share it in the
    // mono font.
    TextMetrics {
        id: digit
        font: number.font
        text: "0"
    }

    Text {
        id: number
        objectName: "number"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.known ? root.format(root.volumeDb) : "—"
        textFormat: Text.PlainText
        font.family: root.theme.fontMono
        font.pixelSize: root.fontPixelSize
        color: root.color
    }

    // On the number's baseline through an anchor: both are one font whose
    // metrics never change at runtime, so the Qt.AlignBaseline rule
    // (docs/DESIGN.md §5) does not apply.
    Text {
        id: unit
        objectName: "unit"
        anchors.left: number.right
        anchors.leftMargin: root.unitGap
        anchors.baseline: number.baseline
        visible: root.known
        text: "dB"
        textFormat: Text.PlainText
        font.family: root.theme.fontMono
        font.pixelSize: Math.round(root.fontPixelSize * 0.7)
        color: root.color
        opacity: 0.6
    }
}
