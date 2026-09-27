// Phase 7.14.0 - the source picker list, a floating card that opens
// UPWARD over the volume/action rows from the source row in
// SourceSelector.qml (mockup v2 `#sourceList`, `.source-list.overlay-popup
// {top:auto; bottom:72px; max-height:252px}`, `.source-option`).
//
// Built on exactly AmpListOverlay.qml's shape - a QtQuick.Controls Popup
// reparented into the flyout window's Overlay, content a synchronous
// ColumnLayout + Repeater inside a ScrollView, height computed from the
// column's implicit height before open() - and deliberately NOT on
// PlasmaComponents3.ComboBox's own popup any more. Why (Phase 7.14.0
// investigation, see TODO.md): the ComboBox popup's ListView only gets
// its model once the popup is visible and reports its height as
// delegates land, while QQuickPopupPositioner shrinks/flips it to fit -
// any outside customization of that popup's height/background races
// that (three live attempts: rows appearing then vanishing, or never
// rendering). The old "ComboBox required per QTBUG-66446" rule turned
// out to be an RTL LayoutMirroring bug filed against Popup in general,
// not a reason to keep ComboBox - the actual Phase 3 failure was
// qqc2-desktop-style's QtQuick.Controls ComboBox using a QStyle-drawn
// Menu as its popup, which a plain Popup never touches. A side benefit:
// PC3 ComboBox's built-in wheel handler that cycled currentIndex on
// scroll over the closed row (each switch forcing -40 dB) is gone.
//
// Self-containment boundary, mirroring AmpListOverlay: inputs `theme`,
// `enabledSources` (already filtered by SourceSelector), and
// `activeSourceIndex`; outputs the `closed` signal (Popup's own) and
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
    // Array of {name, index, enabled, selected} - enabled ones only.
    required property var enabledSources
    required property int activeSourceIndex
    // Phase 9.1.1: chrome alpha for the card background - see
    // TransparencySettings.qml's controlAlpha comment.
    required property TransparencySettings transparencySettings

    signal sourceChosen(int index, string name)

    // Parent is the source row, which already sits inside SourceSelector's
    // 16px side margins - so x:0/full parent width IS the mockup's
    // `.overlay-popup{left:16px; right:16px}` inset, no extra math.
    x: 0
    width: parent ? parent.width : 0

    // Opens upward: card bottom `gap` px above the row's top edge. The
    // mockup pins `bottom:72px` from the flyout's bottom, which lands the
    // card just above the row; 6px is the closest clean reading (verify
    // live - assumption, not a measured mockup value).
    readonly property int gap: 6
    y: -overlay.height - overlay.gap

    // `.source-option{margin:4px}` - CSS vertical margins collapse between
    // siblings, so rows are 4px apart and 4px in from the card edge.
    padding: 4
    readonly property int rowSpacing: 4
    readonly property int maxListHeight: 252

    // The row's top edge in window coordinates, as a LIVE binding (QML
    // tracks every `y`/`parent` read in the loop - same technique as
    // FlyoutPopup.qml's panelSpan.iconOrigin; Item.mapToItem() would
    // give the same number once but never re-evaluate). A plain Popup
    // has no fit-inside-window logic of its own (unlike ComboBox's
    // positioner, which is what used to flip the old dropdown upward),
    // so the card is capped to the space actually above the row.
    readonly property real rowTopInWindow: {
        let y = 0;
        for (let i = overlay.parent; i; i = i.parent) {
            y += i.y;
        }
        return y;
    }
    readonly property real spaceAbove: overlay.rowTopInWindow - overlay.gap - 8

    height: Math.max(
        2 * overlay.padding + 36,
        Math.min(listColumn.implicitHeight + 2 * overlay.padding,
                 overlay.maxListHeight,
                 overlay.spaceAbove))

    modal: false
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: OverlayCardBackground { theme: overlay.theme; transparencySettings: overlay.transparencySettings }

    // Phase 17.1.1: since 17.1.0's shorter flyout, the real amp's six
    // sources no longer fit in the room above the row, so the list
    // scrolls. On open, scroll just far enough that the selected source is
    // fully visible (a ComboBox popup positions itself; this Popup does
    // not), and leave the list at the top when it already is.
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
            // Phase 17.1.1: the ScrollView's own availableWidth, not the
            // Popup's. Under the desktop style the vertical ScrollBar
            // reserves 21 px (rightPadding) once the list scrolls; binding
            // to the Popup's width kept rows 260 px wide in a 239 px
            // viewport, so the bar covered their right edge and the
            // selection tick (measured on the 17.1.0 harness run).
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
                color: overlay.theme.textFaint
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
                    // Pinned (house rule: AlignVCenter children + a row
                    // height equal to the tallest child's real height):
                    // the 20px glyph slot is the tallest child in every state -
                    // the 13px label's implicit height is below it - so
                    // 20 + 2*8 padding.
                    implicitHeight: 36
                    radius: overlay.theme.radiusOverlayRow
                    color: sourceOptionArea.containsMouse ? overlay.theme.surface2 : "transparent"

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 9

                        // Phase 17.7.0: painted 17 px glyph (flyout mockup
                        // v2 :132-133), no box behind it - in either theme,
                        // so it reads right over transparency + blur. The
                        // 20 px slot keeps the objectName (harness key) and
                        // the text position; the mockup's transparent
                        // container is 22 px - spacing alignment is its own
                        // pass.
                        Item {
                            objectName: "sourceOptionChip:" + sourceOption.modelData.index
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            SourceGlyph {
                                anchors.centerIn: parent
                                sourceName: sourceOption.modelData.name
                                size: 17
                                color: overlay.theme.copperBright
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
                            color: sourceOption.isCurrent ? overlay.theme.copperBright : overlay.theme.textDim
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.alignment: Qt.AlignVCenter
                            text: "✓"
                            font.pixelSize: 11
                            color: overlay.theme.copperBright
                            visible: sourceOption.isCurrent
                        }
                    }

                    MouseArea {
                        id: sourceOptionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // Bounds-checked against the model this component
                        // owns (the same rule SourceSelector's old
                        // onActivated followed).
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
