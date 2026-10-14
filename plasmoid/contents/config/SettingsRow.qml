// Settings row, the mockup's .kcm-row: name + description on the left
// (max-width 440), an arbitrary control on the right, a bottom divider.
// `showDivider` (default true) drops the divider where the mockup has
// none: the last row of a group and the page's final row.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../ui" as Ui

ColumnLayout {
    id: root

    property string name: ""
    property string desc: ""
    property bool showDivider: true
    // Per-row padding overrides (e.g. the "Chime sound" row's inline
    // `padding-top:0`, v16 mockup line 481). Defaults are .kcm-row's own
    // 16px (configDialog mockup v30 :267).
    property int topPadding: 16
    property int bottomPadding: 16
    // Optional one-line message between the name/control line and the
    // divider: the mockup's .limit-warning (v16 mockup lines 297-301: mono
    // 10px, danger-bright, right-aligned, padding 0 2px 10px). "" renders
    // nothing. Used for Launch at login's systemd status/error text.
    property string note: ""
    property color noteColor: colors.dangerBright
    default property alias controlData: controlHolder.data

    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded by ConfigGeneral (required, so a
    // missed hand-off fails at load).
    required property Ui.ColorPalette colors

    Layout.fillWidth: true
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: root.topPadding
        Layout.bottomMargin: root.bottomPadding
        spacing: 20

        ColumnLayout {
            Layout.maximumWidth: 440
            Layout.alignment: Qt.AlignVCenter
            // `.kcm-row-text{gap:4px}` (mockup v30 :271).
            spacing: 4

            Label {
                Layout.fillWidth: true
                text: root.name
                font.pixelSize: 14
                font.weight: Font.Medium
                color: root.colors.text
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: root.desc
                visible: root.desc !== ""
                font.pixelSize: 11
                color: root.colors.textFaint
                wrapMode: Text.WordWrap
            }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            id: controlHolder
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.rightMargin: 2
        Layout.bottomMargin: 10
        visible: root.note !== ""
        text: root.note
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.WordWrap
        font.family: root.theme.fontMono
        font.pixelSize: 10
        color: root.noteColor
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        visible: root.showDivider
        color: root.colors.divider
    }
}
