// The flyout's volume block: dB readout, source chip, and the -/slider/+
// row.
//
// Signal-up only, like AmpHeader.qml and AmpListOverlay.qml: no D-Bus or
// exec calls here. FlyoutContent runs devialet-ctl and calls
// pendingAmpState.notifyVolume() in response to stepRequested and
// sliderReleased.
//
// `volumeDb` is PendingAmpState's shared pending-or-confirmed value, not a
// local mirror, so no drag/step debounce is needed here: notifyVolume()
// writes the value in the same tick before its D-Bus call, and the daemon
// resolves confirmed-vs-expired (docs/DESIGN.md §3).
//
// Every dynamic Label is pinned to `wrapMode: Text.NoWrap`, as in
// AmpHeader.qml.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    id: volumeBlock
    objectName: "volumeBlock"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property string ampIp
    // undefined | number - see header comment.
    required property var volumeDb
    // Shared, root-anchored volume-range config (floor/hard-limit/step dB)
    // - see VolumeSettings.qml.
    required property VolumeSettings volumeSettings
    // Feeds colors.controlColor() for the -/+ buttons and the source chip:
    // control fills track the panel alpha with a floor.
    required property TransparencySettings transparencySettings
    required property string activeSourceName
    // The daemon's PowerState ("Off"/"Booting"/"On"), fed from
    // FlyoutContent's own mirror - the same property whose change handler
    // arms PendingAmpState's post-boot hold, so the controls below become
    // interactive in the tick the hold arms, never before.
    required property string powerState

    // Power gate (known-gotchas #10): every volume input needs an amp
    // connected AND On. The amp drops commands while Off or Booting, and
    // the daemon's 400 ms pending mask would then snap the value back, so
    // the control is not offered. The dB readout stays (the amp reports
    // its volume in standby), only dimmed.
    readonly property bool interactive: volumeBlock.ampIp !== "" && volumeBlock.powerState === "On"

    // -1 / +1, one per button click/autoRepeat tick or wheel notch.
    signal stepRequested(int direction)
    // Final value on slider release - FlyoutContent sends it and calls
    // pendingAmpState.notifyVolume().
    signal sliderReleased(real value)

    Layout.fillWidth: true
    Layout.topMargin: 16
    Layout.bottomMargin: 6
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    spacing: 10
    // Whole-group dim when not `interactive` (no amp, or not On) - the
    // same 0.4 factor as the Android app's disabledAlpha.
    opacity: volumeBlock.interactive ? 1.0 : 0.4

    RowLayout {
        id: dbSourceRow
        objectName: "dbSourceRow"
        Layout.fillWidth: true

        RowLayout {
            id: dbValueRow
            objectName: "dbValueRow"
            spacing: 0
            // AlignVCenter children + a pinned height instead of
            // AlignBaseline (docs/DESIGN.md §5). Measured tallest implicit
            // height across "0.0"/"-40.0"/"-60.0"/"—": a constant 35 (the
            // font never changes here, only the text length).
            Layout.preferredHeight: 35

            Label {
                id: dbValueLabel
                objectName: "dbValueLabel"
                Layout.alignment: Qt.AlignVCenter
                // Bound to the slider's live value, not volumeDb, so the
                // readout tracks a drag continuously.
                text: (volumeBlock.ampIp !== "" && volumeBlock.volumeDb !== undefined) ? volumeSlider.value.toFixed(1) : "—"
                font.family: volumeBlock.theme.fontMono
                font.weight: Font.Medium
                font.pixelSize: 26
                // In light the Label only holds the layout
                // (transparent text) and the gold gradient + glow is
                // painted over it, so the row's geometry is the same in
                // both themes.
                color: volumeBlock.colors.isLight ? "transparent" : volumeBlock.colors.copperBright
                wrapMode: Text.NoWrap

                Loader {
                    anchors.fill: parent
                    active: volumeBlock.colors.isLight
                    sourceComponent: GradientText {
                        text: dbValueLabel.text
                        font: dbValueLabel.font
                        startColor: volumeBlock.colors.readoutGradientStart
                        endColor: volumeBlock.colors.readoutGradientEnd
                        glow: true
                        // The token carries the CSS alpha; MultiEffect
                        // takes colour and opacity separately.
                        glowColor: Qt.rgba(volumeBlock.colors.readoutGlow.r, volumeBlock.colors.readoutGlow.g, volumeBlock.colors.readoutGlow.b, 1)
                        glowOpacity: volumeBlock.colors.readoutGlow.a
                    }
                }
            }
            Label {
                id: dbUnitLabel
                objectName: "dbUnitLabel"
                Layout.alignment: Qt.AlignVCenter
                text: "dB"
                font.pixelSize: 12
                color: volumeBlock.colors.textDim
                Layout.leftMargin: 3
                wrapMode: Text.NoWrap
            }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            id: sourceChip
            objectName: "sourceChip"
            Layout.alignment: Qt.AlignVCenter
            // Capped (with the label's elide) so a long source name can't
            // grow the chip once the fillWidth spacer above reaches 0.
            Layout.maximumWidth: 140
            radius: 999
            // Tracks panel alpha with a floor - see
            // ColorPalette.controlColor().
            color: volumeBlock.colors.controlColor(volumeBlock.transparencySettings)
            // Light-theme card shadow (hidden in dark).
            CardShadow { colors: volumeBlock.colors; radius: parent.radius }
            border.width: 1
            border.color: volumeBlock.colors.chipBorder
            implicitWidth: sourceChipLabel.implicitWidth + 18
            implicitHeight: sourceChipLabel.implicitHeight + 6

            Label {
                id: sourceChipLabel
                objectName: "sourceChipLabel"
                anchors.centerIn: parent
                width: parent.width - 18
                horizontalAlignment: Text.AlignHCenter
                text: volumeBlock.activeSourceName !== "" ? volumeBlock.activeSourceName : "—"
                font.family: volumeBlock.theme.fontMono
                // One weight heavier in light (flyout mockup v22 :152-157).
                font.weight: volumeBlock.colors.isLight ? Font.Medium : Font.Normal
                font.pixelSize: 11
                color: volumeBlock.colors.textFaint
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    RowLayout {
        id: sliderRow
        objectName: "sliderRow"
        Layout.fillWidth: true
        spacing: 10

        Button {
            id: volumeDownButton
            objectName: "volumeDownButton"
            text: "−"
            enabled: volumeBlock.interactive
            autoRepeat: true
            autoRepeatDelay: 300
            autoRepeatInterval: 100
            onClicked: volumeBlock.stepRequested(-1)

            implicitWidth: 26
            implicitHeight: 26
            background: Rectangle {
                radius: volumeBlock.theme.radiusSm
                color: volumeBlock.colors.controlColor(volumeBlock.transparencySettings)
                // Light-theme card shadow (hidden in dark).
                CardShadow { colors: volumeBlock.colors; radius: parent.radius }
                border.width: 1
                border.color: parent.hovered ? volumeBlock.colors.copperDim : volumeBlock.colors.controlBorder
            }
            contentItem: Label {
                text: parent.text
                font.family: volumeBlock.theme.fontDisplay
                font.weight: Font.DemiBold
                font.pixelSize: 14
                color: parent.hovered ? volumeBlock.colors.copperBright : volumeBlock.colors.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Slider {
            id: volumeSlider
            objectName: "volumeSlider"
            Layout.fillWidth: true
            // Widens the click/drag hit area to match the sibling -/+
            // buttons' 26 px row height.
            implicitHeight: 26
            from: volumeBlock.volumeSettings.floorDb
            to: volumeBlock.volumeSettings.hardLimitDb
            stepSize: volumeBlock.volumeSettings.stepDb
            enabled: volumeBlock.interactive

            // The daemon-resolved pending-or-confirmed value drives
            // `value` except while dragging - see the header comment for
            // why no other holdout is needed.
            Binding {
                target: volumeSlider
                property: "value"
                value: (volumeBlock.ampIp !== "" && volumeBlock.volumeDb !== undefined) ? volumeBlock.volumeDb : volumeBlock.volumeSettings.floorDb
                when: !volumeSlider.pressed
            }

            onPressedChanged: {
                if (!volumeSlider.pressed) {
                    volumeBlock.sliderReleased(volumeSlider.value);
                }
            }

            background: Rectangle {
                x: volumeSlider.leftPadding
                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                implicitHeight: 4
                width: volumeSlider.availableWidth
                height: 4
                radius: 999
                color: volumeBlock.colors.surface3

                Rectangle {
                    width: volumeSlider.visualPosition * parent.width
                    height: parent.height
                    radius: 999
                    color: volumeBlock.colors.accentFill
                }
            }

            // Flat copperBright disc in dark; in light the mockup's gold
            // sphere (flyout mockup v3 :99-100 - radial
            // #fcecc0/#f0a623/#a8710b, `0 1px 3px rgba(110,72,10,.35)` shadow,
            // 3 px rgba(240,166,35,.14) halo). Same 15 px footprint in both,
            // so nothing moves.
            handle: Item {
                x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                width: 15
                height: 15

                Rectangle {
                    anchors.fill: parent
                    visible: !volumeBlock.colors.isLight
                    radius: 999
                    color: volumeBlock.colors.copperBright
                }
                GoldSphere {
                    anchors.fill: parent
                    visible: volumeBlock.colors.isLight
                    diameter: 15
                    haloWidth: 3
                    shadowColor: "#6e480a"
                    shadowVerticalOffset: 1
                    shadowBlur: 0.2
                }
            }

            // Scroll to adjust volume. acceptedButtons: Qt.NoButton lets
            // press/drag pass through to the Slider underneath (the same
            // technique as org.kde.desktop's own style).
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton

                // Accumulates sub-notch wheel deltas into whole 120-unit
                // "notches" before stepping - one stepRequested() call per
                // physical notch, matching org.kde.desktop's own
                // Slider.qml convention.
                property int wheelDelta: 0

                // Spaces notches into evenly timed steps - see
                // WheelStepPacer.qml and VolumeSettings.wheelStepMinIntervalMs.
                WheelStepPacer {
                    id: wheelPacer
                    intervalMs: volumeBlock.volumeSettings.wheelStepMinIntervalMs
                    onStep: (direction) => volumeBlock.stepRequested(direction)
                }

                function step(direction) {
                    wheelPacer.notch(direction);
                }

                onWheel: (wheel) => {
                    // Blocked while actively dragging - the Slider's
                    // `value` binding above is suppressed until release,
                    // and release unconditionally sends the drag position.
                    if (volumeSlider.pressed) return;

                    const delta = (wheel.angleDelta.y || -wheel.angleDelta.x) * (wheel.inverted ? -1 : 1);
                    wheelDelta += delta;
                    while (wheelDelta >= 120) {
                        wheelDelta -= 120;
                        step(1);
                    }
                    while (wheelDelta <= -120) {
                        wheelDelta += 120;
                        step(-1);
                    }
                }
            }
        }

        Button {
            id: volumeUpButton
            objectName: "volumeUpButton"
            text: "+"
            enabled: volumeBlock.interactive
            autoRepeat: true
            autoRepeatDelay: 300
            autoRepeatInterval: 100
            onClicked: volumeBlock.stepRequested(1)

            implicitWidth: 26
            implicitHeight: 26
            background: Rectangle {
                radius: volumeBlock.theme.radiusSm
                color: volumeBlock.colors.controlColor(volumeBlock.transparencySettings)
                // Light-theme card shadow (hidden in dark).
                CardShadow { colors: volumeBlock.colors; radius: parent.radius }
                border.width: 1
                border.color: parent.hovered ? volumeBlock.colors.copperDim : volumeBlock.colors.controlBorder
            }
            contentItem: Label {
                text: parent.text
                font.family: volumeBlock.theme.fontDisplay
                font.weight: Font.DemiBold
                font.pixelSize: 14
                color: parent.hovered ? volumeBlock.colors.copperBright : volumeBlock.colors.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
