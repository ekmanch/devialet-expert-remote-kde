// Phase 17.16.0 - the settings page's segmented control (mockup
// `.kcm-segmented` / `.kcm-seg-btn`), extracted unchanged from the two
// copies that lived inline in ConfigGeneral.qml (Volume step size, Chime
// sound) so the Theme row (17.17.0) can reuse it instead of a third copy.
//
// Inputs: `labels` (one segment per string), `activeIndex` (bound by the
// page - which segment is on), `colors` (the page palette, required like
// every other settings component). Output: `picked(index)` when a segment
// is clicked; the page writes its cfg_* value in the handler, so this
// component never owns settings state.
//
// Look (unchanged from the inline copies): a `radiusSm` box in `surface`
// with a 1 px `divider` border and 3 px inner padding; segments 2 px apart,
// radius 6, label + 22 px wide and + 10 px tall; the active segment is
// filled `surface3`; labels are 11 px mono, copperBright when active or
// hovered, textDim otherwise. Mockup v25
// `.kcm-seg-btn:not(.active):hover {color:var(--copper-bright)}`: hover
// lights the text only - no background change, no cursor change
// ("segmented hover is text-color only").

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
                color: segment.active ? seg.colors.surface3 : "transparent"
                implicitWidth: segmentLabel.implicitWidth + 22
                implicitHeight: segmentLabel.implicitHeight + 10

                Label {
                    id: segmentLabel
                    anchors.centerIn: parent
                    text: segment.modelData
                    font.family: seg.theme.fontMono
                    font.pixelSize: 11
                    color: segment.active || segmentArea.containsMouse
                        ? seg.colors.copperBright : seg.colors.textDim
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
