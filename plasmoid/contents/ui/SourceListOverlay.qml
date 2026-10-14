// The source picker list: a floating card that opens UPWARD over the
// volume/action rows from the source row in SourceSelector.qml (mockup v2
// `#sourceList`, `.source-list.overlay-popup{top:auto; bottom:72px;
// max-height:252px}`, `.source-option`).
//
// Same shape as AmpListOverlay.qml: a QtQuick.Controls Popup, content a
// synchronous ColumnLayout + Repeater inside a ScrollView, height computed
// from the column's implicit height before open(). Not a ComboBox popup -
// see docs/DESIGN.md §3. No wheel handler on purpose: every source switch
// sends the startup volume (known-gotchas #5).
//
// Inputs `theme`, `enabledSources` (already filtered by SourceSelector)
// and `activeSourceIndex`; outputs the Popup's own `closed` signal and
// `sourceChosen(index, name)`. The owner (FlyoutContent) parents this
// Popup to SourceSelector's row item, drives open()/close() off its own
// `sourceListOpen` state and never binds `visible`.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Popup {
    id: overlay
    objectName: "sourceListOverlay"

    required property Theme theme
    // Colour tokens (ColorPalette.qml), forwarded by the owner.
    required property ColorPalette colors
    // Array of {name, index, enabled, selected} - enabled ones only.
    required property var enabledSources
    required property int activeSourceIndex
    // Card background alpha - see OverlayCardBackground.qml.
    required property TransparencySettings transparencySettings

    signal sourceChosen(int index, string name)

    // Parent is the source row, which already sits inside SourceSelector's
    // 16px side margins - so x:0/full parent width IS the mockup's
    // `.overlay-popup{left:16px; right:16px}` inset, no extra math.
    x: 0
    width: parent ? parent.width : 0

    // Opens upward, its bottom edge over the row's top part. The mockup
    // pins the card `bottom:66px` above the flyout's bottom and caps it at
    // 264 px so six sources fit without a scrollbar (flyout mockup v22
    // :446); six need 244 (6 x 36 + 5 x 4 + 2 x 4). Measured on the live
    // flyout: the row's top is 99 px above the flyout's bottom (y 231 of
    // 330), so the card covers the row's top 33 px.
    readonly property int rowOverlap: 33
    y: -overlay.height + overlay.rowOverlap

    // `.source-option{margin:4px}` - CSS vertical margins collapse between
    // siblings, so rows are 4px apart and 4px in from the card edge.
    padding: 4
    readonly property int rowSpacing: 4
    readonly property int maxListHeight: 264

    // The row's top edge in window coordinates, as a LIVE binding (QML
    // tracks every `y`/`parent` read in the loop - same technique as
    // FlyoutPopup.qml's panelSpan.iconOrigin; Item.mapToItem() would
    // give the same number once but never re-evaluate). A plain Popup
    // has no fit-inside-window logic of its own, so the card is capped to
    // the space actually above the row.
    readonly property real rowTopInWindow: {
        let y = 0;
        for (let i = overlay.parent; i; i = i.parent) {
            y += i.y;
        }
        return y;
    }
    readonly property real spaceAbove: overlay.rowTopInWindow + overlay.rowOverlap - 8

    height: Math.max(
        2 * overlay.padding + 36,
        Math.min(listColumn.implicitHeight + 2 * overlay.padding,
                 overlay.maxListHeight,
                 overlay.spaceAbove))

    modal: false
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: OverlayCardBackground { theme: overlay.theme; colors: overlay.colors; transparencySettings: overlay.transparencySettings }

    // When the list is taller than the card, it scrolls. On open, scroll
    // just far enough that the selected source is fully visible (a Popup
    // does not do this itself), and leave the list at the top when it
    // already is.
    onOpened: overlay.revealCurrent()

    function revealCurrent() {
        const flick = scrollView.contentItem as Flickable;
        let row = null;
        for (let i = 0; i < overlay.enabledSources.length; ++i) {
            if (overlay.enabledSources[i].index === overlay.activeSourceIndex) {
                row = rowRepeater.itemAt(i);
                break;
            }
        }
        if (!flick || !row) return;
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        const wanted = Math.max(0, row.y + row.height - flick.height);
        flick.contentY = Math.min(wanted, maxY);
    }

    contentItem: ScrollView {
        id: scrollView
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: listColumn
            // The ScrollView's own availableWidth, not the Popup's. Under
            // the desktop style the vertical ScrollBar reserves 21 px
            // (rightPadding) once the list scrolls; with the Popup's width
            // the bar would cover the rows' right edge and the tick.
            width: scrollView.availableWidth
            spacing: overlay.rowSpacing

            // Unreachable through the row (SourceSelector disables it when
            // there are no enabled sources) but kept so a programmatic
            // open never shows a bare card.
            Label {
                objectName: "sourceListEmpty"
                visible: overlay.enabledSources.length === 0
                Layout.fillWidth: true
                Layout.margins: 12
                horizontalAlignment: Text.AlignHCenter
                text: "No sources"
                font.family: overlay.theme.fontMono
                font.pixelSize: 11
                color: overlay.colors.textFaint
            }

            Repeater {
                id: rowRepeater
                model: overlay.enabledSources

                // `.source-option`: padding 8px 10px, gap 9, radius 9,
                // 12.5px text-dim (copper-bright + ✓ when selected), hover
                // surface-2, 20x20 chip at 10px.
                delegate: Rectangle {
                    id: sourceOption
                    required property var modelData
                    required property int index
                    objectName: "sourceOption:" + modelData.index
                    readonly property bool isCurrent: modelData.index === overlay.activeSourceIndex

                    Layout.fillWidth: true
                    // Pinned (docs/DESIGN.md §5: AlignVCenter children +
                    // a row height equal to the tallest child's height):
                    // the 20px glyph slot is the tallest child in every state -
                    // the 13px label's implicit height is below it - so
                    // 20 + 2*8 padding.
                    implicitHeight: 36
                    radius: overlay.theme.radiusOverlayRow
                    color: sourceOptionArea.containsMouse ? overlay.colors.surface2 : "transparent"

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 9

                        // Painted 17 px glyph (flyout mockup v2 :132-133),
                        // no box behind it in either theme, so it reads
                        // right over transparency + blur. The 20 px slot
                        // keeps the objectName (harness key) and the text
                        // position; the mockup's container is 22 px.
                        Item {
                            objectName: "sourceOptionChip:" + sourceOption.modelData.index
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            // Gold gradient + warm shadow in light.
                            ThemedSourceGlyph {
                                anchors.centerIn: parent
                                colors: overlay.colors
                                sourceName: sourceOption.modelData.name
                                size: 17
                            }
                        }

                        Label {
                            objectName: "sourceOptionName:" + sourceOption.modelData.index
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            text: sourceOption.modelData.name
                            font.family: overlay.theme.fontDisplay
                            font.weight: Font.DemiBold
                            font.pixelSize: 13
                            color: sourceOption.isCurrent ? overlay.colors.copperBright : overlay.colors.textDim
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }

                        // Painted 16 px tick (flyout mockup v2 :452-453),
                        // not the "✓" character.
                        Tick {
                            objectName: "sourceOptionTick:" + sourceOption.modelData.index
                            Layout.alignment: Qt.AlignVCenter
                            color: overlay.colors.copperBright
                            visible: sourceOption.isCurrent
                        }
                    }

                    MouseArea {
                        id: sourceOptionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // Bounds-checked against the model this component
                        // owns.
                        onClicked: {
                            const i = sourceOption.index;
                            if (i < 0 || i >= overlay.enabledSources.length) return;
                            const chosen = overlay.enabledSources[i];
                            overlay.sourceChosen(chosen.index, chosen.name);
                        }
                    }
                }
            }
        }
    }
}
