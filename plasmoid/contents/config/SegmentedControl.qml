// The settings page's segmented control (mockup `.kcm-segmented` /
// `.kcm-seg-btn`), used by the Theme, Volume step and Chime sound rows.
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../ui" as Ui

Rectangle {
    id: seg

    required property Ui.ColorPalette colors
    property var labels: []
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

                radius: 6
                // In light the selected segment is white
                // with a 1 px outline and label in the text colour, DemiBold
                // (configDialog mockup v30 :95, :106). JetBrains Mono has
                // one advance for every weight, so widths do not change.
                color: segment.active ? seg.colors.segmentActiveFill : "transparent"
                border.width: segment.active && seg.colors.isLight ? 1 : 0
                border.color: seg.colors.segmentActiveBorder
                implicitWidth: segmentLabel.implicitWidth + 22
                implicitHeight: segmentLabel.implicitHeight + 10

                Label {
                    id: segmentLabel
                    anchors.centerIn: parent
                    text: segment.modelData
                    font.family: seg.theme.fontMono
                    font.pixelSize: 11
                    font.weight: segment.active && seg.colors.isLight ? Font.DemiBold : Font.Normal
                    color: segment.active ? seg.colors.segmentActiveText
                        : (segmentArea.containsMouse ? seg.colors.copperBright : seg.colors.textDim)
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
