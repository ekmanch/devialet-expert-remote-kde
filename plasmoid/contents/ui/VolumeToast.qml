// Copper-styled reskin of Plasma's native volume OSD (plasma-workspace's
// shell/osd.cpp, org.kde.plasma.workspace.osd's OsdItem.qml). Only the
// look is ours; the behaviour copies the native one:
//
// - Timing: 1800 ms fixed dismiss, OsdItem.qml's `timeout` default.
// - Rapid repeat: like Osd::showOsd(), every show snaps the content to the
//   new value (no queueing, no fade replay) and restarts the same timer.
// - Placement: `type: OnScreenDisplay` gives the window the same Wayland
//   role the native OSD uses, and Dialog skips its own setPosition() for
//   that type, so the compositor places it (bottom centre), not us.
// - Flags: no Qt.ToolTip. Dialog only strips Qt::Dialog for an OSD, and
//   Qt::ToolTip seeks a transient parent the same way, which makes the
//   position follow whatever last had focus. Like the native OsdWindow we
//   set WindowDoesNotAcceptFocus directly and get WindowTransparentForInput
//   through `outputOnly: true`.
//
// PlasmaCore.Dialog has a real NoBackground hint (the shell's PlasmaWindow
// popups have none), which is what allows the custom card below
// (docs/DESIGN.md §3).
//
// Layout follows the OSD mockup (devialet_volume_osd_mockup_v3 and later):
// icon + name + value + progress bar + source line, with a distinct muted
// treatment. Shared with VolumeHoverTooltip.qml: the icon thresholds and
// paths in Theme.qml (plasma-pa's AudioIcon::forVolume breakpoints) and
// the palette's osdGradientTop/Bottom card gradient.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmaCore.Dialog {
    id: toast

    readonly property Theme theme: Theme {}
    // `colors` is ThemeSettings' OSD/tooltip palette, kept separate from
    // the flyout's (docs/DESIGN.md §6).
    required property ThemeSettings themeSettings
    readonly property ColorPalette colors: toast.themeSettings.osdPalette

    // ---- Content state (set via showVolume()/showMute() below) ----
    property string ampName: ""
    property string sourceName: ""
    property bool muted: false
    property bool isWordValue: false
    property string valueText: ""
    property real fraction: 0
    property string iconKind: "high"

    type: PlasmaCore.Dialog.OnScreenDisplay
    flags: Qt.WindowDoesNotAcceptFocus
    outputOnly: true
    backgroundHints: PlasmaCore.Dialog.NoBackground
    hideOnWindowDeactivate: false

    function showVolume(ampName, sourceName, volumeDb, fraction, muted) {
        toast.ampName = ampName;
        toast.sourceName = sourceName;
        toast.muted = muted;
        // While muted, show "Muted" rather than the dB value (the tooltip's
        // rule). The value label reads isWordValue/valueText, not muted.
        toast.isWordValue = muted;
        toast.valueText = muted ? "Muted" : volumeDb.toFixed(1);
        toast.fraction = fraction;
        // Same icon rule as showMute(): the mute glyph while muted.
        toast.iconKind = muted ? "mute" : toast.theme.volumeIconKindForFraction(fraction);
        dismissTimer.restart();
        toast.visible = true;
    }

    function showMute(ampName, sourceName, muted, fraction) {
        toast.ampName = ampName;
        toast.sourceName = sourceName;
        toast.muted = muted;
        toast.isWordValue = true;
        toast.valueText = muted ? "Muted" : "Unmuted";
        toast.fraction = fraction;
        // Muted always shows the mute glyph; unmuted uses the volume
        // thresholds, as in showVolume().
        toast.iconKind = muted ? "mute" : toast.theme.volumeIconKindForFraction(fraction);
        dismissTimer.restart();
        toast.visible = true;
    }

    // The Timer lives inside mainItem's Rectangle: Dialog's default
    // property (mainItem) is a single QQuickItem*, so a bare child here
    // would fail with "Cannot assign object of type Timer to property of
    // type QQuickItem*".
    mainItem: Rectangle {
        id: card
        implicitWidth: Math.max(340, row.implicitWidth + 36)
        implicitHeight: row.implicitHeight + 28
        radius: toast.theme.radiusLg
        // No outer border (OSD mockup v2 :125). The icon box below keeps
        // its own border.

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: toast.colors.osdGradientTop }
            GradientStop { position: 1.0; color: toast.colors.osdGradientBottom }
        }

        Timer {
            id: dismissTimer
            interval: 1800
            onTriggered: toast.visible = false
        }

        // Fixed left/right margins, not centerIn (mockup padding: 14px 20px
        // 14px 16px). The card floors at 340 px wide, so a centred row would
        // shift inward whenever the value is short ("Muted"). The body's
        // Layout.fillWidth absorbs the slack (`.osd-body{ flex:1 }`).
        RowLayout {
            id: row
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Rectangle {
                id: iconBox
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 10
                // Dark: transparent fill (OSD mockup v3, `--key-bg:
                // transparent`). Light: a white key with the control border
                // and card shadow (OSD mockup v4 :102-103, :134-141).
                color: toast.colors.isLight ? toast.colors.surface : "transparent"
                border.width: 1
                border.color: toast.muted ? toast.colors.copperDim : toast.colors.controlBorder
                CardShadow { colors: toast.colors; radius: parent.radius }

                // The copper glow is dark-only (OSD mockup v4 :145); in
                // light the muted icon carries the gold treatment instead.
                layer.enabled: toast.muted && !toast.colors.isLight
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: toast.colors.copperBright
                    shadowBlur: 0.5
                    shadowOpacity: 0.25
                    shadowScale: 1.25
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    source: toast.theme.volumeIconSources[toast.iconKind]
                    isMask: true
                    color: toast.muted ? toast.colors.copperBright : toast.colors.text
                    visible: !(toast.colors.isLight && toast.muted)
                }

                // Light muted icon: the mute glyph as the mask of the gold
                // gradient with a warm drop shadow (OSD mockup v4
                // :142-150), like ThemedSourceGlyph.qml. A plain hidden
                // Image works as the mask and is rasterised at device
                // pixels.
                Loader {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    active: toast.colors.isLight
                    visible: toast.muted
                    sourceComponent: GradientMask {
                        maskSource: muteMask
                        radial: true
                        radialCenterX: width * 0.32
                        radialCenterY: height * 0.28
                        radialRadius: width * 0.775
                        shadowEnabled: true
                        shadowVerticalOffset: 2
                        shadowBlur: 0.3
                        shadowBlurMax: 16
                        shadowOpacity: 0.35

                        Image {
                            id: muteMask
                            anchors.fill: parent
                            visible: false
                            source: toast.theme.volumeIconSources.mute
                            sourceSize: Qt.size(17, 17)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.bottomMargin: 7
                    Layout.fillWidth: true
                    // The value Label swaps font between the dB number and
                    // the "Muted"/"Unmuted" word, so no AlignBaseline here:
                    // AlignVCenter on both Labels plus a pinned height
                    // (docs/DESIGN.md §5). 20 is the measured tallest
                    // implicit height (value: 20 as a number, 16 as a word;
                    // ampName: 17). Any smaller pin leaves a 1 px shift, as
                    // RowLayout centres on an overflowing child.
                    Layout.preferredHeight: 20

                    Label {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: toast.ampName
                        font.family: toast.theme.fontDisplay
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                        color: toast.colors.text
                        elide: Text.ElideRight
                    }

                    Label {
                        id: valueLabel
                        Layout.alignment: Qt.AlignVCenter
                        text: toast.valueText + (toast.isWordValue ? "" : " dB")
                        font.family: toast.isWordValue ? toast.theme.fontDisplay : toast.theme.fontMono
                        font.weight: toast.isWordValue ? Font.DemiBold : Font.Medium
                        font.pixelSize: toast.isWordValue ? 12 : 15
                        // The number and "Muted" are copper; "Unmuted" is
                        // plain text (the mockup has no "Unmuted" example;
                        // copper marks an active state). In light the Label
                        // only holds the layout for the gold forms and the
                        // overlay below paints them.
                        readonly property bool goldForm: toast.colors.isLight && (!toast.isWordValue || toast.muted)
                        color: valueLabel.goldForm ? "transparent" : (toast.isWordValue ? (toast.muted ? toast.colors.copperBright : toast.colors.text) : toast.colors.copperBright)

                        // Light value (OSD mockup v4 :158-169, :107-110):
                        // the number in the readout's gold sweep with a
                        // 9 px glow and a small grey "dB", right-aligned in
                        // the Label's box; "Muted" in the three-stop gold
                        // text sweep. Painted over the Label, so the row's
                        // geometry is the dark theme's.
                        Loader {
                            anchors.fill: parent
                            active: toast.colors.isLight
                            sourceComponent: Item {
                                Label {
                                    id: lightUnit
                                    visible: !toast.isWordValue
                                    anchors.right: parent.right
                                    anchors.baseline: lightNumber.baseline
                                    text: "dB"
                                    font.family: toast.theme.fontMono
                                    font.pixelSize: 10
                                    color: toast.colors.textDim
                                }
                                GradientText {
                                    id: lightNumber
                                    visible: !toast.isWordValue
                                    anchors.right: lightUnit.left
                                    anchors.rightMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: toast.isWordValue ? "" : toast.valueText
                                    font.family: toast.theme.fontMono
                                    font.weight: Font.Medium
                                    font.pixelSize: 15
                                    startColor: toast.colors.readoutGradientStart
                                    endColor: toast.colors.readoutGradientEnd
                                    glow: true
                                    glowColor: Qt.rgba(toast.colors.readoutGlow.r, toast.colors.readoutGlow.g, toast.colors.readoutGlow.b, 1)
                                    glowOpacity: toast.colors.readoutGlow.a
                                    // 9 px against the flyout readout's 14 px (0.9).
                                    glowBlur: 0.58
                                }
                                GradientText {
                                    visible: toast.isWordValue && toast.muted
                                    anchors.fill: parent
                                    text: "Muted"
                                    font.family: toast.theme.fontDisplay
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 12
                                    startColor: toast.colors.goldTextStart
                                    midColor: toast.colors.goldTextMid
                                    midPos: 0.55
                                    endColor: toast.colors.goldTextEnd
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 4
                    radius: 999
                    color: toast.colors.surface3
                    clip: true

                    Rectangle {
                        height: parent.height
                        width: parent.width * toast.fraction
                        radius: 999
                        // In light: flat gold, #d8d3cb when muted.
                        color: toast.muted ? toast.colors.mutedFill : toast.colors.accentFill
                    }
                }

                Label {
                    Layout.topMargin: 6
                    text: toast.sourceName !== "" ? toast.sourceName : "—"
                    font.family: toast.theme.fontMono
                    font.pixelSize: 10
                    color: toast.colors.textFaint
                }
            }
        }
    }
}
