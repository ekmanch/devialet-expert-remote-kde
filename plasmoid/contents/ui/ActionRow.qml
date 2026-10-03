// Phase 7.5.0 (spike/flyout-appletpopup-rebuild) - the action row
// (mute/power buttons), extracted from FullRepresentation.qml's action
// GridLayout (~1483-1662) into its own self-contained component for the
// FlyoutPopup rebuild, following the AmpHeader.qml/AmpListOverlay.qml/
// VolumeBlock.qml precedent set in Phase 7.3.0/7.4.0. Replaces the next
// chunk of FlyoutContent.qml's `sectionsPlaceholder` spacer - see TODO.md's
// Phase 7.5.0 entry and the plan it cites
// (docs/context-on-spike-flyout-dialog-rebuild-b-quirky-wand.md, §4).
//
// §4 point 2 applied here (task item 2): `powerContentRow` (the RowLayout
// swapping a static Kirigami.Icon for an animated spinner depending on
// `powerState`) gets an explicit `Qt.AlignVCenter` on every child +
// a measured `Layout.preferredHeight` - deliberate policy for this
// rebuild, applied even though the investigation doc's own finding 8-
// adjacent read of this row called it "low-risk today" (both the icon and
// the spinner are already fixed 13x13 `implicitWidth`/`implicitHeight`
// literals, and RowLayout's default per-child alignment has no cross-
// sibling baseline-style contamination the way `Qt.AlignBaseline` does -
// see CLAUDE.md's house rule for why that specific mechanism is what
// makes AlignBaseline dangerous and AlignVCenter safe by construction).
// Height measured via the §5 harness dump across off/Booting/on (see
// TODO.md's Phase 7.5.0 entry) rather than assumed equal just because the
// icon/spinner are both 13x13 - the Label's own text also changes
// ("Power On"/"Power Off"/"Powering on…") so the row's implicit height is
// verified, not asserted.
//
// `muteContentRow` (the mute button's icon+label) gets the identical
// treatment for consistency, even though task item 2 named only the power
// button's icon/spinner swap by name - its Label text is the same
// mute-state-dependent-child class §4 point 2 warns about ("Mute" vs
// "Unmute"), and the fix is free to apply everywhere at once rather than
// waiting for a future phase to notice the gap.
//
// Architecture: pure signal-up, no direct D-Bus/exec calls here - matches
// AmpHeader.qml (toggleRequested), AmpListOverlay.qml (ampChosen), and
// VolumeBlock.qml (stepRequested/sliderReleased). FlyoutContent owns the
// actual devialet-ctl invocation, BeginPowerOnBoot call, and
// pendingAmpState.notifyMute() call in response to
// muteToggleRequested/powerToggleRequested below.
//
// `muted` is fed in from FlyoutContent's `root.pendingAmpState.muted`
// (Phase 5's shared, daemon-resolved value, same architecture VolumeBlock
// already established for volumeDb - task item 3) - not a new local
// mirror. `power`/`powerState` are fed from FlyoutContent's own existing
// D-Bus mirror (established in 7.3.0 for the header's dot color/sub-text)
// - PendingAmpState deliberately does not cover Power/PowerState (see its
// own header comment: "only AmpIp/VolumeDb/Muted are ever processed"), so
// FlyoutContent's root gains its own optimistic-set + 400ms debounce
// guard for Power/PowerState this phase, ported from
// FullRepresentation.qml's `lastPowerChangeAtMs`/`within()` - this one
// genuinely still needs client-side debounce, unlike volume/mute, because
// no daemon-owned pending-command state exists for it (Phase 5.0.0 was
// scoped to VolumeDb/Muted only).

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
    // Phase 17.11.0: colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property string ampIp
    required property bool muted
    required property bool power
    // "Off" | "Booting" | "On"
    required property string powerState
    // Phase 9.1.1: chrome alpha (mute/power button backgrounds) - see
    // TransparencySettings.qml's controlAlpha comment.
    required property TransparencySettings transparencySettings

    signal muteToggleRequested()
    signal powerToggleRequested()

    // 2026-09-08 follow-up: mute is interactive only with the amp on -
    // the same `interactive` gate VolumeBlock.qml got the same day, for
    // the same reason (the amp drops the command while off/booting and
    // the daemon's 400 ms pending mask snaps the optimistic state back).
    // Applied to the mute button alone, not the row: the power button
    // beside it must stay live while the amp is off. The label keeps its
    // last-known Mute/Unmute text, only dimmed.
    readonly property bool muteInteractive: actionRow.ampIp !== "" && actionRow.powerState === "On"

    // Phase 17.4.0: a fixed 11:14 split (flyout mockup v2 :403-408,
    // `grid-template-columns: 11fr 14fr`): never content-sized, so nothing
    // moves when a label changes (Mute/Unmute, Power Off/Power On/
    // Powering on…), and Power gets the larger share so "Powering on…"
    // plus its spinner has room. Replaces the 2026-09-12 split (Phase
    // 12.0.0), which measured each button's widest content with
    // TextMetrics and gave both equal worst-case margins (108 / 152 px);
    // the mockup now fixes the ratio instead. actionRow.width comes from
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
    // Same whole-group dim as the header/volume block above (Android's
    // setGroupEnabled(actionRow, connected)).
    opacity: actionRow.ampIp === "" ? 0.4 : 1.0

    Button {
        id: muteButton
        objectName: "muteButton"
        Layout.fillWidth: true
        // See actionRow's equal-margin split above.
        Layout.preferredWidth: actionRow.muteButtonWidth
        Layout.preferredHeight: 38
        enabled: actionRow.muteInteractive
        // Same 0.4 factor as the group dims / Phase 8.3.0's steppers.
        opacity: actionRow.muteInteractive ? 1.0 : 0.4
        onClicked: actionRow.muteToggleRequested()

        // Phase 9.1.1: the non-muted (plain surface) branch tracks panel
        // alpha with a floor - see TransparencySettings.qml's controlAlpha
        // comment. The muted branch's 0.14 copper tint is a deliberate,
        // orthogonal state-highlight (not "is this button solid against
        // the desktop"), left untouched.
        background: Rectangle {
            radius: actionRow.theme.radiusMd
            color: actionRow.muted
                ? actionRow.colors.activeFill
                : actionRow.colors.controlColor(actionRow.transparencySettings)
                // Phase 17.19.0: light-theme card shadow (hidden in dark).
                CardShadow { colors: actionRow.colors; radius: parent.radius; visible: actionRow.colors.isLight && !actionRow.muted }
            border.width: 1
            border.color: actionRow.muted ? actionRow.colors.copperDim : (parent.hovered ? actionRow.colors.copperDim : actionRow.colors.controlBorder)
        }
        contentItem: RowLayout {
            id: muteContentRow
            objectName: "muteContentRow"
            spacing: 6
            // See this file's header comment - extended §4 point 2
            // treatment, measured via the harness dump across mute
            // on/off: a constant implicitHeight of 14 (see TODO.md's
            // Phase 7.5.0 entry). Note this pin is honestly decorative
            // here, not load-bearing the way VolumeBlock.qml's
            // `dbValueRow` pin is: `contentItem` is sized by the Button
            // control itself (fills the full 38px button height, per
            // QQC2's own contentItem geometry management, confirmed by
            // the harness dump's own h:38 vs ih:14), not read via
            // QtQuick.Layouts' attached properties the way a real nested
            // Layout-in-Layout row is - kept anyway per this rebuild's
            // blanket policy, and harmless.
            Layout.preferredHeight: 14

            Item { Layout.fillWidth: true }
            Kirigami.Icon {
                id: muteIcon
                objectName: "muteIcon"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 13
                implicitHeight: 13
                // Phase 17.3.0 (owner decision D7): the button shows the
                // ACTION a click performs, like its label - while audible,
                // "Mute" with the muted speaker (X); while muted, "Unmute"
                // with the speaker and waves (flyout mockup v2 :565-566,
                // toggleMute()). The OSD is not interactive and keeps
                // showing the STATE instead (VolumeToast.qml). Bundled SVGs
                // since 17.2.0 (Theme.volumeIconSources, the v2 mockup's
                // filled speaker): identical under every icon theme and a
                // mask source for the light theme's gold glyph. isMask so
                // `color` paints it. 13x13 in both states, so
                // muteContentRow's height pin is unaffected.
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
        // See actionRow's equal-margin split above.
        Layout.preferredWidth: actionRow.powerButtonWidth
        Layout.preferredHeight: 38
        // Genuinely inert during boot, not just visually dimmed -
        // `enabled: false` on a QQC2 Button blocks mouse/keyboard event
        // delivery outright, matching the mockup's `pointer-events:none`
        // for .state-booting - the primary defense against click-spam
        // (the daemon's own BeginPowerOnBoot no-op guard is
        // defense-in-depth, not a substitute for this).
        enabled: actionRow.ampIp !== "" && actionRow.powerState !== "Booting"
        onClicked: actionRow.powerToggleRequested()

        // Phase 9.1.1: tracks panel alpha with a floor - see
        // TransparencySettings.qml's controlAlpha comment.
        background: Rectangle {
            radius: actionRow.theme.radiusMd
            color: actionRow.colors.controlColor(actionRow.transparencySettings)
            // Phase 17.19.0: light-theme card shadow (hidden in dark).
            CardShadow { colors: actionRow.colors; radius: parent.radius }
            border.width: 1
            // Booting takes priority over the hover colors below it,
            // which stay completely untouched - the mockup's
            // .state-booting rule isn't a :hover variant, it applies
            // unconditionally while booting.
            border.color: actionRow.powerState === "Booting"
                ? actionRow.colors.warning
                : (powerButton.hovered ? (actionRow.power ? actionRow.colors.danger : actionRow.colors.success) : actionRow.colors.controlBorder)
        }
        contentItem: RowLayout {
            id: powerContentRow
            objectName: "powerContentRow"
            spacing: 6
            // §4 point 2 fix (task item 2) - see this file's header
            // comment. Measured via the harness dump across
            // off/Booting/on: a constant implicitHeight of 14 across all
            // three (see TODO.md's Phase 7.5.0 entry) - both the icon and
            // the spinner are fixed 13x13 literals and the Label's font
            // never swaps, only its text. Same "decorative, not
            // load-bearing" caveat as muteContentRow's own pin above
            // (contentItem is Button-sized, not Layout-sized) - kept per
            // this rebuild's blanket policy regardless.
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

            // Literal port of the mockup's .spinner (a static dim ring
            // plus a rotating bright ~90° arc, via QtQuick.Shapes'
            // PathAngleArc - not a theme-dependent shape, just self-drawn
            // geometry, so none of the corner-radius Known Issue's
            // Darkly-matching concerns apply here).
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
