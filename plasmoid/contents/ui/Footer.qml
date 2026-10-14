// The footer connection-status line: a read-only row (dot + label), no
// interaction or signals.
//
// Known, harmless wobble: despite `Layout.fillWidth: true`, the row's
// measured width tracks its content, so with `Qt.AlignHCenter` the whole
// row recentres when the text changes length ("Connected" / "Not
// connected" / "Not responding"). It is the last row in mainColumn and its
// height never changes, so nothing else moves. Allowlisted in
// tools/flyout-harness/expected-17.json.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: footer
    objectName: "footer"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property string ampIp
    required property bool online

    Layout.fillWidth: true
    Layout.topMargin: 9
    Layout.bottomMargin: 11
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    Layout.alignment: Qt.AlignHCenter

    Rectangle {
        id: footerDot
        objectName: "footerDot"
        Layout.alignment: Qt.AlignVCenter
        // 7 px with an 8 px gap to the label (flyout mockup v22 :466-472,
        // the header's dot-to-text proportion); in light the connected dot
        // is the gold sphere with the header dot's shadow scaled down
        // (:474-476).
        width: 7
        height: 7
        radius: 3.5
        // Centred on the label's capital height, not on its 14 px line box
        // (which includes descender space): box-centred, the disc measured
        // 0.75 px below the centre of "Connected". A 2 px bottom margin
        // lifts the vertically centred dot by 1 px.
        Layout.bottomMargin: 2
        readonly property bool gold: footer.colors.isLight && footer.online
        color: footerDot.gold ? "transparent" : (footer.online ? footer.colors.copperBright : footer.colors.textFaint)
        Loader {
            anchors.centerIn: parent
            active: footer.colors.isLight
            visible: footerDot.gold
            sourceComponent: GoldSphere {
                diameter: 7
                shadowVerticalOffset: 1.5
                shadowBlur: 0.25
            }
        }
    }

    Label {
        objectName: "footerLabel"
        // 3 + the row's 5 px spacing = the 8 px gap.
        Layout.leftMargin: 3
        text: footer.ampIp === "" ? "Not connected" : (footer.online ? "Connected" : "Not responding")
        font.family: footer.theme.fontMono
        // One weight heavier in light (flyout mockup v22 :152-157).
        font.weight: footer.colors.isLight ? Font.Medium : Font.Normal
        font.pixelSize: 10
        color: footer.colors.textFaint
        wrapMode: Text.NoWrap
    }
}
