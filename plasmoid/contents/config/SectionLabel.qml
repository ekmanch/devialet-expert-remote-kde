// Section header, the mockup's .kcm-section-label: display font,
// uppercase, letter-spaced, followed by a divider filling the remaining
// width (the mockup's ::after, here a RowLayout of label + line).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../ui" as Ui

RowLayout {
    id: root

    property string text: ""
    // The first section label on the page, right under the brand header,
    // gets the mockup's smaller `.first` top margin.
    property bool first: false

    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded by ConfigGeneral (required, so a
    // missed hand-off fails at load).
    required property Ui.ColorPalette colors

    Layout.fillWidth: true
    // `.kcm-section-label{margin:40px 0 10px}`, first one 2px on top
    // (configDialog mockup v30 :261-265).
    Layout.topMargin: root.first ? 2 : 40
    Layout.bottomMargin: 10
    spacing: 8

    Label {
        id: heading
        text: root.text
        font.family: root.theme.fontDisplay
        // In light, Bold with the gold sweep clipped to the
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
