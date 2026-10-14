// The flyout's action row: the mute and power buttons.
//
// Signal-up only, like AmpHeader.qml, AmpListOverlay.qml and
// VolumeBlock.qml: no D-Bus or exec calls here. FlyoutContent runs
// devialet-ctl, BeginPowerOnBoot and pendingAmpState.notifyMute() in
// response to muteToggleRequested / powerToggleRequested.
//
// `muted` is PendingAmpState's shared, daemon-resolved value.
// `power`/`powerState` come from FlyoutContent's own D-Bus mirror, which
// has its own optimistic set + 400 ms click guard: the daemon's pending
// command state covers only VolumeDb/Muted, not power.
//
// Both content rows (icon + label) use AlignVCenter children and a
// pinned height (docs/DESIGN.md §5), since their labels change with
// state ("Mute"/"Unmute", "Power On"/"Power Off"/"Powering on…").

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

GridLayout {
    id: actionRow
    objectName: "actionRow"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property string ampIp
    required property bool muted
    required property bool power
    // "Off" | "Booting" | "On"
    required property string powerState
    // Feeds colors.controlColor() for the button backgrounds: control
    // fills track the panel alpha with a floor.
    required property TransparencySettings transparencySettings

    signal muteToggleRequested()
    signal powerToggleRequested()

    // Power gate (known-gotchas #10): mute is interactive only with the
    // amp On, like VolumeBlock's `interactive`. Applied to the mute button
    // alone, not the row: the power button must stay live while the amp
    // is off. The label keeps its last-known Mute/Unmute text, dimmed.
    readonly property bool muteInteractive: actionRow.ampIp !== "" && actionRow.powerState === "On"

    // A fixed 11:14 split (flyout mockup v2 :403-408,
    // `grid-template-columns: 11fr 14fr`): never content-sized, so nothing
    // moves when a label changes (Mute/Unmute, Power Off/Power On/
    // Powering on…), and Power gets the larger share so "Powering on…"
    // plus its spinner has room. actionRow.width comes from
    // mainColumn, anchored to FlyoutContent's constant-width root, so
    // deriving preferredWidth from it can't loop back into the flyout's
    // own implicit width. At the 300 px panel: row 268 px (16 px side
    // margins), minus the 8 px column spacing = 260 px -> 114 / 146 px
    // (the mockup's 259.5 px -> 114.2 / 145.3).
    readonly property real buttonsAvailable: actionRow.width - actionRow.columnSpacing
    // Whole pixels: the mute button rounds, the power button takes the
    // exact remainder so the two always sum to the row (no sub-pixel
    // borders on either).
    readonly property int muteButtonWidth: Math.round(actionRow.buttonsAvailable * 11 / 25)
    readonly property int powerButtonWidth: actionRow.buttonsAvailable - actionRow.muteButtonWidth

    Layout.fillWidth: true
    Layout.topMargin: 14
    Layout.bottomMargin: 4
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    columns: 2
    columnSpacing: 8
    rowSpacing: 8
    // Whole-row dim with no amp only (Android's setGroupEnabled(actionRow,
    // connected)). Unlike VolumeBlock it can't dim on "not On": the power
    // button must stay live while the amp is Off, so mute dims itself.
    opacity: actionRow.ampIp === "" ? 0.4 : 1.0

    Button {
        id: muteButton
        objectName: "muteButton"
        Layout.fillWidth: true
        // See actionRow's 11:14 split above.
        Layout.preferredWidth: actionRow.muteButtonWidth
        Layout.preferredHeight: 38
        enabled: actionRow.muteInteractive
        // Own 0.4 dim only while the row isn't already dimmed (no amp):
        // opacities multiply, and 0.4 x 0.4 would leave mute fainter than
        // the power button and the volume block.
        opacity: (actionRow.ampIp === "" || actionRow.muteInteractive) ? 1.0 : 0.4
        onClicked: actionRow.muteToggleRequested()

        // The non-muted branch tracks panel alpha with a floor (see
        // ColorPalette.controlColor()). The muted branch's tint is a
        // state highlight, independent of the panel transparency.
        background: Rectangle {
            radius: actionRow.theme.radiusMd
            color: actionRow.muted
                ? actionRow.colors.activeFill
                : actionRow.colors.controlColor(actionRow.transparencySettings)
                // Light-theme card shadow (hidden in dark).
                CardShadow { colors: actionRow.colors; radius: parent.radius; visible: actionRow.colors.isLight && !actionRow.muted }
            border.width: 1
            border.color: actionRow.muted ? actionRow.colors.copperDim : (parent.hovered ? actionRow.colors.copperDim : actionRow.colors.controlBorder)
        }
        contentItem: RowLayout {
            id: muteContentRow
            objectName: "muteContentRow"
            spacing: 6
            // Measured implicitHeight across mute on/off: a constant 14.
            // The pin is decorative here: a Button sizes its contentItem
            // itself (the full 38 px height), not via Layout attached
            // properties. Kept for consistency; harmless.
            Layout.preferredHeight: 14

            Item { Layout.fillWidth: true }
            Kirigami.Icon {
                id: muteIcon
                objectName: "muteIcon"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 13
                implicitHeight: 13
                // The button shows the ACTION a click performs, like its
                // label - while audible, "Mute" with the muted speaker (X);
                // while muted, "Unmute" with the speaker and waves (flyout
                // mockup v2 :565-566, toggleMute()). The OSD is not
                // interactive and shows the STATE instead (VolumeToast.qml).
                // Bundled SVGs (Theme.volumeIconSources): identical under
                // every icon theme and a mask source for the light theme's
                // gold glyph. isMask so `color` paints it. 13x13 in both
                // states, so muteContentRow's height pin is unaffected.
                source: actionRow.theme.volumeIconSources[actionRow.muted ? "high" : "mute"]
                isMask: true
                color: actionRow.muted ? actionRow.colors.copperBright : actionRow.colors.text
            }
            Label {
                id: muteLabel
                objectName: "muteLabel"
                Layout.alignment: Qt.AlignVCenter
                text: actionRow.muted ? "Unmute" : "Mute"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: actionRow.muted ? actionRow.colors.copperBright : actionRow.colors.text
                wrapMode: Text.NoWrap
            }
            Item { Layout.fillWidth: true }
        }
    }

    Button {
        id: powerButton
        objectName: "powerButton"
        Layout.fillWidth: true
        // See actionRow's 11:14 split above.
        Layout.preferredWidth: actionRow.powerButtonWidth
        Layout.preferredHeight: 38
        // Inert during boot, not just dimmed: `enabled: false` blocks
        // mouse/keyboard delivery (the mockup's `pointer-events:none` for
        // .state-booting). This is the primary guard against click-spam;
        // the daemon's BeginPowerOnBoot no-op guard is only a backstop.
        enabled: actionRow.ampIp !== "" && actionRow.powerState !== "Booting"
        onClicked: actionRow.powerToggleRequested()

        // Tracks panel alpha with a floor - see ColorPalette.controlColor().
        background: Rectangle {
            radius: actionRow.theme.radiusMd
            color: actionRow.colors.controlColor(actionRow.transparencySettings)
            // Light-theme card shadow (hidden in dark).
            CardShadow { colors: actionRow.colors; radius: parent.radius }
            border.width: 1
            // Booting takes priority over the hover colors: the mockup's
            // .state-booting rule applies unconditionally, not on :hover.
            border.color: actionRow.powerState === "Booting"
                ? actionRow.colors.warning
                : (powerButton.hovered ? (actionRow.power ? actionRow.colors.danger : actionRow.colors.success) : actionRow.colors.controlBorder)
        }
        contentItem: RowLayout {
            id: powerContentRow
            objectName: "powerContentRow"
            spacing: 6
            // Measured implicitHeight across off/Booting/on: a constant
            // 14 (icon and spinner are both fixed 13x13; the Label's font
            // never changes, only its text). Decorative, like
            // muteContentRow's pin above.
            Layout.preferredHeight: 14

            Item { Layout.fillWidth: true }

            Kirigami.Icon {
                id: powerIcon
                objectName: "powerIcon"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 13
                implicitHeight: 13
                source: "system-shutdown-symbolic"
                color: powerButton.hovered ? (actionRow.power ? actionRow.colors.danger : actionRow.colors.successBright) : actionRow.colors.text
                visible: actionRow.powerState !== "Booting"
            }

            // Port of the mockup's .spinner: a static dim ring plus a
            // rotating bright 90° arc (QtQuick.Shapes' PathAngleArc).
            Item {
                id: powerSpinner
                objectName: "powerSpinner"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 13
                implicitHeight: 13
                visible: actionRow.powerState === "Booting"

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(actionRow.colors.warningBright.r, actionRow.colors.warningBright.g, actionRow.colors.warningBright.b, 0.25)
                }

                Shape {
                    anchors.fill: parent
                    rotation: 0
                    RotationAnimation on rotation {
                        running: powerSpinner.visible
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 700
                    }
                    ShapePath {
                        strokeWidth: 2
                        strokeColor: actionRow.colors.warningBright
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: powerSpinner.width / 2
                            centerY: powerSpinner.height / 2
                            radiusX: powerSpinner.width / 2 - 1
                            radiusY: powerSpinner.height / 2 - 1
                            startAngle: -90
                            sweepAngle: 90
                        }
                    }
                }
            }

            Label {
                id: powerLabel
                objectName: "powerLabel"
                Layout.alignment: Qt.AlignVCenter
                text: actionRow.powerState === "Booting" ? "Powering on…" : (actionRow.power ? "Power Off" : "Power On")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: actionRow.powerState === "Booting"
                    ? actionRow.colors.warningBright
                    : (powerButton.hovered ? (actionRow.power ? actionRow.colors.danger : actionRow.colors.successBright) : actionRow.colors.text)
                wrapMode: Text.NoWrap
            }
            Item { Layout.fillWidth: true }
        }
    }
}
