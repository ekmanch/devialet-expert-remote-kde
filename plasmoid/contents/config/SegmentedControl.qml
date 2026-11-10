// The settings page's segmented control (mockup `.kcm-segmented` /
// `.kcm-seg-btn`), used by the Theme, Icon Style, Volume step and Chime
// sound rows.
//
// Stateless: `activeIndex` is bound by the page and `picked(index)` fires
// on click; the page writes its cfg_* value, so this component never owns
// settings state.
//
// Look: a `radiusSm` box with a 1 px `divider` border and 3 px inner
// padding; segments 2 px apart, radius 6, label + 22 px wide and + 10 px
// tall; labels 11 px mono. Hover lights the label text only, no
// background or cursor change (mockup v25
// `.kcm-seg-btn:not(.active):hover {color:var(--copper-bright)}`).
//
// `glyphStyles` (optional, one PanelGlyph style per label) leads each
// segment with a 14 px copy of that panel glyph in the label's own colour
// (configDialog mockup v31 `.kcm-seg-btn.with-glyph` :207-212: gap 6,
// left padding 8 instead of 11; drawn at 0.6, :758-759).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../ui" as Ui

Rectangle {
    id: seg

    required property Ui.ColorPalette colors
    property var labels: []
    property var glyphStyles: []
    property int activeIndex: -1

    signal picked(int index)

    readonly property Ui.Theme theme: Ui.Theme {}

    radius: seg.theme.radiusSm
    color: seg.colors.surface
    border.width: 1
    border.color: seg.colors.divider
    // Light-theme card shadow (configDialog mockup v30 :115).
    Ui.CardShadow { colors: seg.colors; radius: seg.radius }
    implicitWidth: segRow.implicitWidth + 6
    implicitHeight: segRow.implicitHeight + 6

    RowLayout {
        id: segRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: seg.labels

            Rectangle {
                id: segment
                required property string modelData
                required property int index
                readonly property bool active: seg.activeIndex === segment.index
                readonly property string glyphStyle: seg.glyphStyles[segment.index] ?? ""
                readonly property bool hasGlyph: segment.glyphStyle !== ""
                readonly property color labelColor: segment.active ? seg.colors.segmentActiveText
                    : (segmentArea.containsMouse ? seg.colors.copperBright : seg.colors.textDim)

                radius: 6
                // In light the selected segment is white
                // with a 1 px outline and label in the text colour, DemiBold
                // (configDialog mockup v30 :95, :106). JetBrains Mono has
                // one advance for every weight, so widths do not change.
                color: segment.active ? seg.colors.segmentActiveFill : "transparent"
                border.width: segment.active && seg.colors.isLight ? 1 : 0
                border.color: seg.colors.segmentActiveBorder
                implicitWidth: segmentLabel.implicitWidth + (segment.hasGlyph ? 8 + 14 + 6 + 11 : 22)
                implicitHeight: segmentLabel.implicitHeight + 10

                // The same component the panel draws (docs/DESIGN.md §8).
                Loader {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    active: segment.hasGlyph
                    sourceComponent: Ui.PanelGlyph {
                        size: 14
                        style: segment.glyphStyle
                        glyphState: "normal"
                        fraction: 0.6
                        color: segment.labelColor
                    }
                }

                Label {
                    id: segmentLabel
                    anchors.verticalCenter: parent.verticalCenter
                    // Centred without a glyph; 11 px from the right edge
                    // with one, which is the same place.
                    anchors.right: parent.right
                    anchors.rightMargin: 11
                    text: segment.modelData
                    font.family: seg.theme.fontMono
                    font.pixelSize: 11
                    font.weight: segment.active && seg.colors.isLight ? Font.DemiBold : Font.Normal
                    color: segment.labelColor
                }

                MouseArea {
                    id: segmentArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: seg.picked(segment.index)
                }
            }
        }
    }
}
