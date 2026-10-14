// Hover tooltip for the panel icon, in the widget's own look rather than
// the shell's tooltip styling.
//
// Its own PlasmaCore.Dialog, not PlasmoidItem.toolTipItem: the shell's
// ToolTipDialog is a PlasmaWindow, whose BackgroundHints have no
// NoBackground, so it always paints a frame behind the content. Dialog
// has a real NoBackground (as in VolumeToast.qml). `type: Tooltip` gives
// it the shell tooltip's Wayland role. main.qml sets toolTipMainText/
// toolTipSubText to explicit empty strings so ToolTipArea::isValid() is
// false and the shell's default tooltip (metadata Name/Comment) never
// shows alongside this one (see main.qml).
//
// Positioning is not hand-computed: Dialog::popupPosition() places a
// Dialog with `visualParent` and `location` on the far side of
// `location`, centred on the parent - the same thing ToolTipArea does
// with Plasmoid.location.
//
// Show/hide timing (toolTipDelay before showing, 200 ms before hiding,
// as in ToolTipArea/ToolTipDialog) and hiding it while the flyout is open
// are driven by CompactRepresentation.qml; this file only reacts to
// `visible`.
//
// Layout follows the tooltip mockup (devialet_tray_tooltip_mockup_v4 and
// later): a small status dot by the amp name, no icon box; "Muted"
// replaces the dB reading. The card gradient and radius match
// VolumeToast.qml.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmaCore.Dialog {
    id: tooltip

    property string ampName: ""
    property string sourceName: ""
    property var volumeDb: undefined
    property real volumeFraction: 0
    property bool hasAmp: false
    property bool muted: false

    readonly property Theme theme: Theme {}
    // `colors` is ThemeSettings' OSD/tooltip palette, kept separate from
    // the flyout's (docs/DESIGN.md §6).
    required property ThemeSettings themeSettings
    readonly property ColorPalette colors: tooltip.themeSettings.osdPalette
    readonly property bool isWordValue: tooltip.hasAmp && tooltip.muted

    type: PlasmaCore.Dialog.Tooltip
    flags: Qt.WindowDoesNotAcceptFocus
    backgroundHints: PlasmaCore.Dialog.NoBackground
    location: Plasmoid.location
    hideOnWindowDeactivate: false

    mainItem: Rectangle {
        id: card
        implicitWidth: 172
        implicitHeight: column.implicitHeight + 18
        radius: tooltip.theme.radiusLg
        // No outer border (tooltip mockup v2 :122).

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: tooltip.colors.osdGradientTop }
            GradientStop { position: 1.0; color: tooltip.colors.osdGradientBottom }
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.topMargin: 9
            anchors.bottomMargin: 9
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 0

            RowLayout {
                id: nameRow
                spacing: 6
                // Not the mockup's literal margin-bottom:5px (nor statRow's
                // 6px): the mockup's rhythm (stat row hugging the bar, gaps
                // ~70:100) comes from its own font metrics, likely web fonts
                // failing to load from file://. The literal values render
                // near-equal gaps here, so these margins were measured to
                // match the mockup's look instead.
                Layout.bottomMargin: 7

                // 7 px, no glow in dark (tooltip mockup v2 :133).
                Rectangle {
                    id: dot
                    width: 7; height: 7
                    radius: 3.5
                    color: tooltip.colors.isLight ? "transparent" : tooltip.colors.copperBright
                    // The gold sphere in light (tooltip mockup v5 :98-99,
                    // :132-134; shadow 0 1px 2px).
                    Loader {
                        anchors.centerIn: parent
                        active: tooltip.colors.isLight
                        sourceComponent: GoldSphere {
                            diameter: 7
                            shadowVerticalOffset: 1
                            shadowBlur: 0.25
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: tooltip.ampName
                    font.family: tooltip.theme.fontDisplay
                    font.weight: Font.DemiBold
                    font.pixelSize: 11
                    color: tooltip.colors.text
                    elide: Text.ElideRight
                }
            }

            // Flat children, no nested RowLayout for the value+unit pair: a
            // nested layout has no font baseline of its own, so the pair and
            // the source name would not line up.
            RowLayout {
                id: statRow
                spacing: 1
                Layout.bottomMargin: 4
                // Pinned: the "dB" Label drops out of layout when muted
                // (16 vs 18 px implicit), and that swing also moved nameRow
                // above by a pixel. 18 is the taller, unmuted height.
                //
                // Every child uses AlignVCenter, not AlignBaseline: the
                // value Label swaps font between number and "Muted" and the
                // "dB" Label comes and goes, so a shared baseline would move
                // the source name too (docs/DESIGN.md §5).
                Layout.preferredHeight: 18

                Label {
                    Layout.alignment: Qt.AlignVCenter
                    text: tooltip.hasAmp && tooltip.sourceName !== "" ? tooltip.sourceName : "—"
                    font.family: tooltip.theme.fontMono
                    font.pixelSize: 10
                    color: tooltip.colors.textFaint
                }

                Item { Layout.fillWidth: true }

                Label {
                    id: valueLabel
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        if (!tooltip.hasAmp) return "—";
                        if (tooltip.muted) return "Muted";
                        return tooltip.volumeDb !== undefined ? tooltip.volumeDb.toFixed(1) : "—";
                    }
                    font.family: tooltip.isWordValue ? tooltip.theme.fontDisplay : tooltip.theme.fontMono
                    font.weight: tooltip.isWordValue ? Font.DemiBold : Font.Medium
                    font.pixelSize: tooltip.isWordValue ? 12 : 13
                    // In light the Label holds the layout and the readout's
                    // gold sweep with a 7 px glow is painted over it, "Muted"
                    // included (tooltip mockup v5 :145-150).
                    color: tooltip.colors.isLight ? "transparent" : tooltip.colors.copperBright

                    Loader {
                        anchors.fill: parent
                        active: tooltip.colors.isLight
                        sourceComponent: GradientText {
                            text: valueLabel.text
                            font: valueLabel.font
                            startColor: tooltip.colors.readoutGradientStart
                            endColor: tooltip.colors.readoutGradientEnd
                            glow: true
                            glowColor: Qt.rgba(tooltip.colors.readoutGlow.r, tooltip.colors.readoutGlow.g, tooltip.colors.readoutGlow.b, 1)
                            glowOpacity: tooltip.colors.readoutGlow.a
                            // 7 px against the flyout readout's 14 px (0.9).
                            glowBlur: 0.45
                        }
                    }
                }
                Label {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !tooltip.isWordValue
                    text: "dB"
                    font.pixelSize: 9
                    color: tooltip.colors.textDim
                }
            }

            Rectangle {
                id: barTrack
                Layout.fillWidth: true
                Layout.bottomMargin: 7
                height: 2.5
                radius: 999
                color: tooltip.colors.surface3
                clip: true

                Rectangle {
                    height: parent.height
                    width: parent.width * tooltip.volumeFraction
                    radius: 999
                    // In light: flat gold, #d8d3cb when muted.
                    color: tooltip.muted ? tooltip.colors.mutedFill : tooltip.colors.accentFill
                }
            }

            ColumnLayout {
                spacing: 2

                RowLayout {
                    spacing: 3
                    Label { text: "Scroll"; font.family: tooltip.theme.fontMono; font.weight: Font.Medium; font.pixelSize: 9; color: tooltip.colors.textDim }
                    Label { text: "to adjust"; font.family: tooltip.theme.fontMono; font.pixelSize: 9; color: tooltip.colors.textFaint }
                }
                RowLayout {
                    spacing: 3
                    Label { text: "Middle-click"; font.family: tooltip.theme.fontMono; font.weight: Font.Medium; font.pixelSize: 9; color: tooltip.colors.textDim }
                    Label { text: "to mute"; font.family: tooltip.theme.fontMono; font.pixelSize: 9; color: tooltip.colors.textFaint }
                }
            }
        }
    }
}
