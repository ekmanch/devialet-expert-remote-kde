// The flyout's source selector: the CLOSED row only (mockup v2
// `.source-row`) - a clickable card (icon chip, "Source" eyebrow over the
// current source name, caret) shaped like AmpHeader.qml (`listOpen` in,
// `toggleRequested()` out). The dropdown is SourceListOverlay.qml, a
// Popup that FlyoutContent parents to this row via `rowItem` and
// opens/closes itself, as with AmpHeader + AmpListOverlay
// (docs/DESIGN.md §3).
//
// Placeholder: "No source" (the Android app's `no_source_label`) when no
// amp is connected. The name label is fillWidth + ElideRight in a
// fixed-width row, so switching between "No source" and a real name (up
// to the protocol's 16-char slot) can't move the chip (fixed 24x24,
// first) or the caret (last).
//
// Every row child is AlignVCenter and the row height is a measured
// literal (docs/DESIGN.md §5) - see `rowHeight` below.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    id: sourceSelector
    objectName: "sourceSelector"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    required property string ampIp
    // Raw array of {name, index, enabled, selected} objects - see
    // FlyoutContent's `unwrapSources()`/`fetchSourcesFresh()` for how
    // this stays fresh (Sources is array-of-struct, same "don't trust the
    // PropertiesChanged delta, re-fetch on signal" treatment as
    // KnownAmps).
    required property var sources
    required property int activeSourceIndex
    required property string activeSourceName
    // "Off" | "Booting" | "On", from FlyoutContent's mirror. Power gate
    // (known-gotchas #10): the row is selectable only while the amp is
    // On. The last-known source name stays shown, dimmed.
    required property string powerState
    // Feeds colors.controlColor() for the row background: control fills
    // track the panel alpha with a floor.
    required property TransparencySettings transparencySettings
    // Owner-driven open state (FlyoutContent.sourceListOpen) - drives the
    // caret only; the Popup itself is opened/closed by the owner.
    required property bool listOpen

    signal toggleRequested()

    // Filtered here (this component owns the source model), handed to
    // SourceListOverlay by the owner.
    readonly property var enabledSources: sourceSelector.sources.filter(function (s) { return s.enabled; })
    // The Popup's positioning parent - FlyoutContent sets
    // `SourceListOverlay.parent` to this.
    readonly property alias rowItem: sourceRow

    readonly property bool interactive: sourceSelector.ampIp !== "" && sourceSelector.powerState === "On" && sourceSelector.enabledSources.length > 0

    // "No source" when nothing is selected - see header.
    readonly property string displayName: {
        if (sourceSelector.ampIp === "") return "No source";
        if (sourceSelector.activeSourceName !== "") return sourceSelector.activeSourceName;
        for (var i = 0; i < sourceSelector.enabledSources.length; i++) {
            if (sourceSelector.enabledSources[i].index === sourceSelector.activeSourceIndex) return sourceSelector.enabledSources[i].name;
        }
        return "";
    }

    Layout.fillWidth: true
    Layout.topMargin: 10
    Layout.bottomMargin: 14
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    spacing: 0
    // Same whole-group dim as the blocks above (Android's
    // setGroupEnabled(soundControls, connected)), keyed on `interactive`
    // so an off/booting amp dims the row too.
    opacity: sourceSelector.interactive ? 1.0 : 0.4

    // `.source-row`: surface bg, 1px divider border (copper-dim on hover),
    // 11px radius, padding 9px 10px, gap 10.
    Rectangle {
        id: sourceRow
        objectName: "sourceRow"

        // Measured, not bound: the tallest child across every name state
        // is the two-line label stack - 14 (eyebrow) + 1 spacing + 17
        // (name) = 32, identical for "Optical 1", the 16-char "Chromecast
        // Audio" and "No source". 32 + 2*9 padding = 50 (mockup
        // `.source-row{padding:9px 10px}`).
        readonly property int rowHeight: 32
        Layout.fillWidth: true
        implicitHeight: sourceRow.rowHeight + 18
        radius: sourceSelector.theme.radiusMd
        // Tracks panel alpha with a floor - see ColorPalette.controlColor().
        color: sourceSelector.colors.controlColor(sourceSelector.transparencySettings)
        // Light-theme card shadow (hidden in dark).
        CardShadow { colors: sourceSelector.colors; radius: parent.radius }
        border.width: 1
        border.color: sourceRowArea.containsMouse && sourceSelector.interactive ? sourceSelector.colors.copperDim : sourceSelector.colors.controlBorder

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            // Shows the ACTIVE source's glyph (the mockup's static ◉ was
            // a shortcut): a painted 20 px glyph (flyout mockup v2
            // :126-131), no box behind it; optical when no amp is
            // connected. The 24 px slot keeps the objectName (harness key)
            // and the text position; the mockup's container is 26 px.
            Item {
                objectName: "sourceIconBadge"
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                // Gold gradient + warm shadow in light.
                ThemedSourceGlyph {
                    anchors.centerIn: parent
                    colors: sourceSelector.colors
                    sourceName: sourceSelector.ampIp === "" ? "" : sourceSelector.displayName
                    size: 20
                }
            }

            ColumnLayout {
                id: sourceLabelStack
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                spacing: 1

                Label {
                    objectName: "sourceEyebrow"
                    Layout.fillWidth: true
                    text: "SOURCE"
                    font.family: sourceSelector.theme.fontMono
                    // One weight heavier in light (flyout mockup v22 :152-157).
                    font.weight: sourceSelector.colors.isLight ? Font.Medium : Font.Normal
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: sourceSelector.colors.textFaint
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                Label {
                    objectName: "sourceRowName"
                    Layout.fillWidth: true
                    text: sourceSelector.displayName
                    font.family: sourceSelector.theme.fontDisplay
                    font.weight: Font.DemiBold
                    font.pixelSize: 13
                    color: sourceSelector.colors.text
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            // `.source-caret` - rotates 180° and turns copper while open,
            // same as AmpHeader.qml's ampCaret.
            Label {
                objectName: "sourceCaret"
                Layout.alignment: Qt.AlignVCenter
                text: "⌄"
                font.pixelSize: 11
                color: sourceSelector.listOpen ? sourceSelector.colors.copperBright : sourceSelector.colors.textFaint
                rotation: sourceSelector.listOpen ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: sourceRowArea
            objectName: "sourceRowArea"
            anchors.fill: parent
            hoverEnabled: true
            enabled: sourceSelector.interactive
            onClicked: sourceSelector.toggleRequested()
        }
    }
}
