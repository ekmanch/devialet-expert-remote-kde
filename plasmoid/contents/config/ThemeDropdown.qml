// The mockup's `.theme-dropdown` (v16 configDialog mockup, DOM lines
// 509-520, CSS lines 259-283): the Chime sound "theme" variant's picker of
// installed sound themes.
//
// A plain Popup, as for the flyout's overlay lists (docs/DESIGN.md §3):
// content in a synchronous ColumnLayout + Repeater so its size is known
// before open(), opened and closed imperatively (`visible` is never
// bound), dismissed by Escape or a press outside the field. Not a QQC2
// ComboBox: its qqc2-desktop-style popup is a QStyle-drawn Menu that
// cannot be restyled to this look.
//
// Stateless: `themes` is [{id, name, path}] (id = sound-theme directory
// name, name = display name), `currentId` is bound by the caller, and
// `themeChosen(id)` reports a pick for the caller to store. The label
// shows `currentId`'s display name, falling back to the raw id when it is
// not in `themes`, as KDE's Sound Theme KCM does
// (plasma-workspace kcms/soundtheme/kcm_soundtheme.cpp:113-120).
//
// The mockup's `.theme-dropdown-list` box-shadow is not drawn. Radii:
// field 7px in the mockup -> theme.radiusSm (8), list 8px = radiusSm,
// rows 6px.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import "../ui" as Ui

Rectangle {
    id: root

    property var themes: []
    property string currentId: ""

    signal themeChosen(string id)

    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded by ConfigGeneral (required, so a
    // missed hand-off fails at load).
    required property Ui.ColorPalette colors
    readonly property bool open: list.opened

    function nameFor(id) {
        for (let i = 0; i < root.themes.length; i++) {
            if (root.themes[i].id === id) return root.themes[i].name;
        }
        return id;
    }

    function close() {
        list.close();
    }

    // `.theme-dropdown-field`: min-width 150, padding 6px 8px 6px 12px.
    implicitWidth: Math.max(150, fieldRow.implicitWidth + 12 + 8)
    implicitHeight: fieldRow.implicitHeight + 12
    radius: root.theme.radiusSm
    color: root.colors.surface
    border.width: 1
    border.color: fieldArea.containsMouse ? root.colors.copperDim : root.colors.controlBorder
    // Light-theme card shadow.
    Ui.CardShadow { colors: root.colors; radius: root.radius }

    RowLayout {
        id: fieldRow
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: root.nameFor(root.currentId)
            font.family: root.theme.fontMono
            font.pixelSize: 11
            color: root.colors.text
            elide: Text.ElideRight
        }

        // `.chev`: 12px chevron, textFaint, rotates 180deg and turns
        // copperBright while open (mockup line 512: stroke-width 2.4,
        // path "M6 9l6 6 6-6").
        Shape {
            id: chev
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            scale: 12 / 24
            rotation: root.open ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 150 } }
            ShapePath {
                strokeWidth: 2.4
                strokeColor: root.open ? root.colors.copperBright : root.colors.textFaint
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M6 9l6 6 6-6" }
            }
        }
    }

    MouseArea {
        id: fieldArea
        anchors.fill: parent
        hoverEnabled: true
        // Mockup toggleThemeDropdown(): a click on the field toggles.
        onClicked: {
            if (list.opened) list.close();
            else list.open();
        }
    }

    // `.theme-dropdown-list`: top: calc(100% + 4px); right: 0;
    // min-width: 100%; surface-2, divider border, radius 8, padding 4.
    Popup {
        id: list
        parent: root
        y: root.height + 4
        x: root.width - width
        width: Math.max(root.width, listColumn.implicitWidth + leftPadding + rightPadding)
        padding: 4
        // Required for CloseOnEscape: a Popup only receives the key if it
        // took focus on open (as in AmpListOverlay/SourceListOverlay).
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            radius: root.theme.radiusSm
            // Own token: light `surface2` is a translucent hover fill, not
            // a card colour.
            color: root.colors.listBackground
            border.width: 1
            border.color: root.colors.divider
        }

        contentItem: ColumnLayout {
            id: listColumn
            spacing: 0

            Repeater {
                model: root.themes

                // `.theme-dropdown-item`: padding 6px 8px, radius 6, mono
                // 11px textDim, hover surface3, selected copperBright with
                // a 12px-wide check that is otherwise invisible.
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: row.modelData.id === root.currentId

                    Layout.fillWidth: true
                    implicitWidth: rowContent.implicitWidth + 16
                    implicitHeight: rowContent.implicitHeight + 12
                    radius: 6
                    color: rowArea.containsMouse ? root.colors.listHover : "transparent"

                    RowLayout {
                        id: rowContent
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Label {
                            Layout.preferredWidth: 12
                            text: "✓"
                            font.pixelSize: 10
                            color: root.colors.copperBright
                            opacity: row.selected ? 1.0 : 0.0
                        }

                        Label {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            font.family: root.theme.fontMono
                            font.pixelSize: 11
                            color: row.selected ? root.colors.copperBright : root.colors.textDim
                            wrapMode: Text.NoWrap
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // Mockup selectTheme(): report, then close.
                        onClicked: {
                            root.themeChosen(row.modelData.id);
                            list.close();
                        }
                    }
                }
            }
        }
    }
}
