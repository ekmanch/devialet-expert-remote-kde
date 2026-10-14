// The amp header row: dot, DEVIALET eyebrow, amp name and subtitle, and
// the caret that toggles the amp list (AmpListOverlay.qml). In-flow in
// mainColumn.
//
// Every Label pins `wrapMode: Text.NoWrap` + `maximumLineCount: 1`. The
// row height is a measured literal and every row child is
// Qt.AlignVCenter, never Qt.AlignBaseline, so a font or content change in
// one label cannot move a sibling (docs/DESIGN.md §5).
//
// Owns its own 1px bottom divider (the mockup's `.amp-header
// border-bottom`), so mainColumn sees a single fixed-height item for the
// whole header.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: ampHeaderBg
    objectName: "ampHeader"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property string ampIp
    required property string headerName
    required property string headerSub
    required property bool online
    required property bool power
    required property string powerState
    required property bool listOpen

    signal toggleRequested()

    // Measured, not bound: ampHeaderRow's implicit height is 46 in every
    // amp state (14px display + 11px mono + 10px mono eyebrow, 2px
    // spacing; checked with the harness dump for 0, 1 and 2 known amps).
    // 46 + 26 padding = 72. Pinned so no label font or content change can
    // alter the header's contribution to mainColumn's height.
    readonly property int rowHeight: 46
    Layout.fillWidth: true
    implicitHeight: ampHeaderBg.rowHeight + 26
    color: ampHeaderArea.containsMouse ? ampHeaderBg.colors.headerHover : "transparent"
    // This hover fill is the only thing painted into the flyout's top
    // corners besides FlyoutContent's tint Rectangle, so its top corners
    // follow the flyout's 16px radius (theme.radiusLg); otherwise a hover
    // paints square corners over the rounded ones. Bottom corners stay
    // square (the header ends at its divider). Per-corner radii are Qt 6.7+.
    topLeftRadius: ampHeaderBg.theme.radiusLg
    topRightRadius: ampHeaderBg.theme.radiusLg

    RowLayout {
        id: ampHeaderRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 40
        spacing: 10

        Rectangle {
            id: ampDot
            objectName: "ampDot"
            Layout.alignment: Qt.AlignVCenter
            // 10 px, not the mockup's 12 (flyout v2 :140): a solid disc
            // reads heavier than the outlined 20 px source glyphs. 10
            // matches the amp list's dots.
            width: 10
            height: 10
            radius: 5
            // Lifted 1 px (2 px bottom margin on a vertically centred item)
            // so the disc is centred on the amp name's capital height;
            // centred on the three-line block it measured 1 px low. Same
            // correction as Footer.qml's dot.
            Layout.bottomMargin: 2
            // In light the connected dot is the gold sphere (flyout mockup
            // v22 :143-147); booting, not responding and the no-amp ring
            // stay flat.
            readonly property bool gold: ampHeaderBg.colors.isLight && ampHeaderBg.ampIp !== "" && ampHeaderBg.powerState !== "Booting" && ampHeaderBg.online
            color: ampHeaderBg.ampIp === "" || ampDot.gold ? "transparent" : (ampHeaderBg.powerState === "Booting" ? ampHeaderBg.colors.warningBright : (ampHeaderBg.online ? ampHeaderBg.colors.copperBright : ampHeaderBg.colors.textFaint))
            Loader {
                anchors.centerIn: parent
                active: ampHeaderBg.colors.isLight
                visible: ampDot.gold
                sourceComponent: GoldSphere { diameter: 10 }
            }
            border.width: ampHeaderBg.ampIp === "" ? 1.5 : 0
            border.color: ampHeaderBg.colors.textFaint
            property real pulseOpacity: 1.0
            opacity: ampHeaderBg.powerState === "Booting" ? ampDot.pulseOpacity : (ampHeaderBg.online && !ampHeaderBg.power ? 0.3 : 1.0)
            SequentialAnimation on pulseOpacity {
                running: ampHeaderBg.powerState === "Booting"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.35; duration: 550; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.35; to: 1.0; duration: 550; easing.type: Easing.InOutQuad }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                id: ampEyebrow
                objectName: "ampEyebrow"
                Layout.fillWidth: true
                text: "DEVIALET"
                font.family: ampHeaderBg.theme.fontMono
                // Semibold gold wordmark in light (flyout mockup v22
                // :117-120); the Label holds the layout and the
                // gradient is painted over the word itself (contentWidth,
                // the mockup's `width:fit-content`).
                font.weight: ampHeaderBg.colors.isLight ? Font.DemiBold : Font.Normal
                font.pixelSize: 10
                font.letterSpacing: 1.2
                color: ampHeaderBg.colors.isLight ? "transparent" : ampHeaderBg.colors.textFaint
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight

                Loader {
                    width: ampEyebrow.contentWidth
                    height: ampEyebrow.height
                    active: ampHeaderBg.colors.isLight
                    sourceComponent: GradientText {
                        text: ampEyebrow.text
                        font: ampEyebrow.font
                        startColor: ampHeaderBg.colors.eyebrowGradientStart
                        endColor: ampHeaderBg.colors.eyebrowGradientEnd
                    }
                }
            }

            Label {
                objectName: "ampName"
                Layout.fillWidth: true
                text: ampHeaderBg.headerName
                font.family: ampHeaderBg.theme.fontDisplay
                font.weight: Font.DemiBold
                font.pixelSize: 14
                color: ampHeaderBg.colors.text
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Label {
                objectName: "ampSub"
                Layout.fillWidth: true
                text: ampHeaderBg.headerSub
                font.family: ampHeaderBg.theme.fontMono
                // One weight heavier in light (flyout mockup v22 :152-157).
                font.weight: ampHeaderBg.colors.isLight ? Font.Medium : Font.Normal
                font.pixelSize: 11
                color: ampHeaderBg.colors.textFaint
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }

        Label {
            id: ampCaret
            objectName: "ampCaret"
            Layout.alignment: Qt.AlignVCenter
            text: "⌄"
            font.pixelSize: 11
            color: ampHeaderBg.listOpen ? ampHeaderBg.colors.copperBright : ampHeaderBg.colors.textFaint
            rotation: ampHeaderBg.listOpen ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }

    // The header's own bottom edge (mockup's `.amp-header border-bottom`),
    // always visible - not a mainColumn sibling divider.
    Rectangle {
        objectName: "ampHeaderDivider"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: ampHeaderBg.colors.divider
    }

    MouseArea {
        id: ampHeaderArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ampHeaderBg.toggleRequested()
    }
}
