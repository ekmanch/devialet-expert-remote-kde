// Phase 7.6.0 (spike/flyout-appletpopup-rebuild) - the footer connection-
// status line, extracted from FullRepresentation.qml's footer RowLayout
// (~1807-1831) into its own self-contained component, following the
// AmpHeader.qml/AmpListOverlay.qml/VolumeBlock.qml/ActionRow.qml/
// SourceSelector.qml precedent set in 7.3.0-7.6.0. Replaces the last
// chunk of FlyoutContent.qml's `sectionsPlaceholder` spacer - fully
// consuming it, see TODO.md's Phase 7.6.0 entry.
//
// Split from SourceSelector.qml (task item 1's "your call" on
// splitting) rather than folded into one file: this is a purely
// presentational, read-only status line (no interaction, no signal, no
// command surface - `online`/`ampIp` are already plain scalars
// FlyoutContent has carried since 7.3.0 for the header), a genuinely
// different concern from the source selector's interactive
// model/command/signal surface. Matches how 7.3.0 split AmpHeader
// (in-flow, interactive) from AmpListOverlay (out-of-flow, its own
// model) along a similar natural seam.
//
// Ported verbatim, including the pre-existing
// `Layout.fillWidth: true` + `Layout.alignment: Qt.AlignHCenter`
// combination on the row itself (not reconciled or "fixed" here - not
// one of the investigation document's flagged findings or §4 points,
// out of scope for this phase).
//
// Empirically NOT inert, despite `Layout.fillWidth: true` looking like it
// should force this row to span mainColumn's full available width and
// make `Layout.alignment: Qt.AlignHCenter` moot: confirmed via the §5
// harness dump that `footer`'s own measured width tracks its content
// (`footerDot` + `footerLabel`), not mainColumn's width, and the whole
// row visibly recenters (its window-space x shifts) whenever the status
// text's length changes ("Connected" <-> "Not connected"/"Not
// responding") - `footerDot`/`footerLabel`'s own x *relative to `footer`*
// never changes, only the parent row's position as a whole. Not a §4
// point 5 case (none of the three strings is a placeholder/fallback form
// - they're three alternate real-content strings) and not a master-
// finding risk either (this is the last row in mainColumn - nothing below
// it for the width change to cascade into, and its own height never
// changes) - allowlisted in expected-7.6.0.json as a confirmed-harmless,
// inherited-unchanged cosmetic recentering wobble, not silently ignored.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: footer
    objectName: "footer"

    required property Theme theme
    // Phase 17.11.0: colour tokens (ColorPalette.qml), forwarded by the owner.
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
        // Phase 17.21.0: 5 -> 7 px and the gap to the label 10 -> 8 px in
        // both themes (flyout mockup v22 :466-472, the header's dot-to-text
        // proportion); in light the connected dot is the gold sphere with
        // the header dot's shadow scaled down (:474-476).
        width: 7
        height: 7
        radius: 3.5
        // Centred on the label's capital height, not on its 14 px line box
        // (which includes the descender space): measured on the 2x capture
        // 20261003-141949, the box-centred disc sat 0.75 px below the
        // centre of "Connected" and shared its baseline, and the light
        // sphere's shadow below it made it read lower still. A 2 px bottom
        // margin lifts the vertically centred dot by 1 px.
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
        // Phase 17.19.3: one weight heavier in light (flyout mockup v22 :152-157).
        font.weight: footer.colors.isLight ? Font.Medium : Font.Normal
        font.pixelSize: 10
        color: footer.colors.textFaint
        wrapMode: Text.NoWrap
    }
}
