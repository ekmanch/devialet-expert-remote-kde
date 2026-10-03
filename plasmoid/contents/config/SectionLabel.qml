// Phase 4.4.1: reusable section header, matching the mockup's
// .kcm-section-label (font-display, uppercase, letter-spaced, copperBright,
// with a divider line filling the remaining width via ::after) - built
// as a RowLayout(label, divider-line) since QML has no ::after equivalent.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../ui" as Ui

RowLayout {
    id: root

    property string text: ""
    // Mockup's .kcm-section-label.first has margin-top:2px instead of 28px
    // (the very first section label on the page, right under the brand
    // header) - everything else uses the default top margin.
    property bool first: false

    readonly property Ui.Theme theme: Ui.Theme {}
    // Phase 17.14.0: the page's palette, forwarded by ConfigGeneral (one
    // palette for the whole page; required, so a missed hand-off fails at
    // load instead of silently painting a different palette).
    required property Ui.ColorPalette colors

    Layout.fillWidth: true
    // `.kcm-section-label{margin:40px 0 10px}`, first one 2px on top
    // (configDialog mockup v30 :261-265); were 28 / 6 until 2026-10-03.
    Layout.topMargin: root.first ? 2 : 40
    Layout.bottomMargin: 10
    spacing: 8

    Label {
        id: heading
        text: root.text
        font.family: root.theme.fontDisplay
        // Phase 17.26.0: in light, Bold with the gold sweep clipped to the
        // word (configDialog mockup v30 :90, :99-105). The Label holds the
        // layout with transparent text; GradientText paints over it.
        font.weight: root.colors.isLight ? Font.Bold : Font.DemiBold
        font.pixelSize: 11
        font.letterSpacing: 1.4
        font.capitalization: Font.AllUppercase
        color: root.colors.isLight ? "transparent" : root.colors.copperBright

        Loader {
            anchors.fill: parent
            active: root.colors.isLight
            sourceComponent: Ui.GradientText {
                text: heading.text
                font: heading.font
                startColor: root.colors.goldTextStart
                midColor: root.colors.goldTextMid
                midPos: 0.55
                endColor: root.colors.goldTextEnd
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: root.colors.divider
    }
}
