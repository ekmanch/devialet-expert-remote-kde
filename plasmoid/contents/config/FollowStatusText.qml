// Phase 17.26.0 - the text of a settings-page status line: mono 11 px
// textDim `prefix` followed by a bold `value` ("Following your desktop's
// color scheme — currently Dark").
//
// Dark: one StyledText Label with the value in bold copperBright, exactly
// what ConfigGeneral.qml declared inline before. Light: the value "gets the
// same gold sweep as the section headings" (configDialog mockup v30
// :109-114) - the same Label draws the value transparent (so the layout is
// identical) and a GradientText paints it at the prefix's advance width.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../ui" as Ui

Label {
    id: status

    required property Ui.ColorPalette colors
    readonly property Ui.Theme theme: Ui.Theme {}
    // Plain text; `prefix` ends with the space before the value.
    property string prefix: ""
    property string value: ""

    function escapeStyledText(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    textFormat: Text.StyledText
    text: status.escapeStyledText(status.prefix) + "<font color=\""
        + (status.colors.isLight ? "#00000000" : status.colors.copperBright) + "\"><b>"
        + status.escapeStyledText(status.value) + "</b></font>"
    font.family: status.theme.fontMono
    font.pixelSize: 11
    color: status.colors.textDim

    TextMetrics {
        id: prefixMetrics
        font: status.font
        text: status.prefix
    }

    Loader {
        x: prefixMetrics.advanceWidth
        height: status.height
        active: status.colors.isLight
        sourceComponent: Ui.GradientText {
            text: status.value
            font.family: status.theme.fontMono
            font.pixelSize: 11
            font.bold: true
            startColor: status.colors.goldTextStart
            midColor: status.colors.goldTextMid
            midPos: 0.55
            endColor: status.colors.goldTextEnd
        }
    }
}
