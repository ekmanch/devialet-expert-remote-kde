// The amp picker list: an overlay card under the amp header, outside
// mainColumn's flow, so neither opening it nor the amp count can move
// anything below the header.
//
// A QtQuick.Controls Popup, not a second PlasmaCore.Dialog: its content
// is reparented into the flyout window's own Overlay, so no new native
// window opens and the flyout's hideOnWindowDeactivate / requestActivate
// focus handling is not disturbed. SourceListOverlay.qml has the same
// shape (docs/DESIGN.md §3).
//
// Inputs `theme`, `knownAmps`, `ampIp`; outputs the Popup's own `closed`
// signal and `ampChosen(ip)`. The owner never binds this Popup's
// `visible` (a closePolicy dismissal calls close() imperatively and would
// break such a binding) - it drives open()/close() and listens to
// `closed`.
//
// Styling: mockup v2 `.overlay-popup` / `.amp-option` - a floating card
// inset 16px from the flyout's edges with the shared
// OverlayCardBackground, 8px inner padding (`.amp-list-inner{padding:8px}`)
// and 9px row radius. The None row, divider and empty label are Android
// app behaviour no mockup draws. The connected dot's glow (`box-shadow`)
// is skipped, as on AmpHeader's own dot.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Popup {
    id: overlay
    objectName: "ampListOverlay"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property var knownAmps
    required property string ampIp
    // Card background alpha - see OverlayCardBackground.qml.
    required property TransparencySettings transparencySettings

    signal ampChosen(string ip)

    // Inset card directly under the header (parent): `.overlay-popup
    // {left:16px; right:16px}` + `#ampList{top:64px}` (the header's own
    // bottom edge in the mockup).
    readonly property int inset: 16
    x: overlay.inset
    y: parent ? parent.height : 0
    width: parent ? parent.width - 2 * overlay.inset : 0
    // Capped height; beyond it the ScrollView scrolls. Popup padding is
    // the card's inner padding (`.amp-list-inner{padding:8px}`); height =
    // content + 2*padding.
    padding: 8
    readonly property int maxListHeight: 230
    height: Math.min(listColumn.implicitHeight + 2 * overlay.padding, overlay.maxListHeight)

    modal: false
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: OverlayCardBackground { theme: overlay.theme; colors: overlay.colors; transparencySettings: overlay.transparencySettings }

    contentItem: ScrollView {
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: listColumn
            width: overlay.availableWidth
            spacing: 2

            // ---- "None" row (as in the Android app) ----
            Rectangle {
                id: ampNoneOption
                objectName: "ampNoneRow"
                readonly property bool isCurrent: overlay.ampIp === ""

                Layout.fillWidth: true
                implicitHeight: ampNoneRow.implicitHeight + 16
                radius: overlay.theme.radiusOverlayRow
                color: ampNoneArea.containsMouse ? overlay.colors.surface2 : "transparent"

                RowLayout {
                    id: ampNoneRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 8
                    spacing: 9

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        // 10 px, matching the amp rows' dots below (the
                        // mockup has no "None" row).
                        width: 10
                        height: 10
                        radius: 5
                        color: "transparent"
                        border.width: 1.5
                        border.color: ampNoneOption.isCurrent ? overlay.colors.copperBright : overlay.colors.textFaint
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            Layout.fillWidth: true
                            text: "None"
                            font.family: overlay.theme.fontDisplay
                            font.weight: Font.DemiBold
                            font.italic: true
                            font.pixelSize: 13
                            color: ampNoneOption.isCurrent ? overlay.colors.copperBright : overlay.colors.textDim
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: "Don't connect to any amplifier"
                            font.family: overlay.theme.fontMono
                            font.pixelSize: 10
                            color: overlay.colors.textFaint
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }
                    }

                    // Painted 16 px tick (flyout mockup v2 :452-453),
                    // not the "✓" character.
                    Tick {
                        objectName: "ampNoneTick"
                        Layout.alignment: Qt.AlignVCenter
                        color: overlay.colors.copperBright
                        visible: ampNoneOption.isCurrent
                    }
                }

                MouseArea {
                    id: ampNoneArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: overlay.ampChosen("")
                }
            }

            Rectangle {
                objectName: "ampListDivider"
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 2
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                height: 1
                color: overlay.colors.divider
            }

            Label {
                objectName: "ampListEmpty"
                visible: overlay.knownAmps.length === 0
                Layout.fillWidth: true
                Layout.margins: 12
                horizontalAlignment: Text.AlignHCenter
                text: "No amps discovered yet"
                font.family: overlay.theme.fontMono
                font.pixelSize: 11
                color: overlay.colors.textFaint
            }

            Repeater {
                model: overlay.knownAmps

                delegate: Rectangle {
                    id: ampOption
                    required property var modelData
                    objectName: "ampOption:" + modelData.ip
                    readonly property bool isCurrent: overlay.ampIp !== "" && modelData.ip === overlay.ampIp
                    readonly property string displayName: modelData.modelName !== "" ? modelData.modelName : modelData.deviceName

                    Layout.fillWidth: true
                    implicitHeight: ampOptionRow.implicitHeight + 16
                    radius: overlay.theme.radiusOverlayRow
                    color: ampOptionArea.containsMouse ? overlay.colors.surface2 : "transparent"

                    RowLayout {
                        id: ampOptionRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 8
                        spacing: 9

                        Rectangle {
                            id: ampOptionDot
                            Layout.alignment: Qt.AlignVCenter
                            // 10 px (flyout mockup v2 :141,
                            // `.amp-option-dot`).
                            width: 10
                            height: 10
                            radius: 5
                            // The connected amp's dot is the
                            // gold sphere in light (flyout mockup v22
                            // :144-146).
                            readonly property bool gold: overlay.colors.isLight && ampOption.isCurrent
                            color: ampOptionDot.gold ? "transparent" : (ampOption.isCurrent ? overlay.colors.copperBright : overlay.colors.textFaint)
                            Loader {
                                anchors.centerIn: parent
                                active: overlay.colors.isLight
                                visible: ampOptionDot.gold
                                sourceComponent: GoldSphere { diameter: 10 }
                            }
                            opacity: ampOption.modelData.online ? 1.0 : 0.5
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: ampOption.displayName !== "" ? ampOption.displayName : ampOption.modelData.ip
                                font.family: overlay.theme.fontDisplay
                                font.weight: Font.DemiBold
                                font.pixelSize: 13
                                color: ampOption.isCurrent ? overlay.colors.copperBright : overlay.colors.textDim
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: ampOption.modelData.ip
                                    + (ampOption.modelData.online ? "" : " · offline")
                                    + (ampOption.modelData.modelName !== "" ? "" : " · name unresolved")
                                font.family: overlay.theme.fontMono
                                font.pixelSize: 10
                                color: overlay.colors.textFaint
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                        }

                        // Painted 16 px tick, as above.
                        Tick {
                            objectName: "ampOptionTick:" + ampOption.modelData.ip
                            Layout.alignment: Qt.AlignVCenter
                            color: overlay.colors.copperBright
                            visible: ampOption.isCurrent
                        }
                    }

                    MouseArea {
                        id: ampOptionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: overlay.ampChosen(ampOption.modelData.ip)
                    }
                }
            }
        }
    }
}
