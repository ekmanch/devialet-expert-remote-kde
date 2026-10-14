// The flyout window: a PlasmaCore.Dialog with NoBackground, the only
// popup class that drops the theme frame and so allows real transparency
// (docs/DESIGN.md §3). No KWin blur: plain alpha over the desktop, like
// the tooltip and toast.
//
// - `appletInterface` is deliberately not set. With it set,
//   Dialog::hideEvent() writes popupWidth/popupHeight into the applet's
//   KConfig on every hide, and the only reader returns early anyway
//   because the Layout min/max hints below are equal.
//
// - `visualParent` is `panelSpan`, not the icon item. Dialog anchors the
//   popup to the visualParent's own bounds, so anchoring to the icon
//   would overlap the panel by the gap between icon and panel edge.
//   panelSpan covers the panel's full thickness instead (see its comment).
//
// - Overlay.overlay reset (Qt 6.11 bug): QQuickOverlay places itself at
//   -(contentItem.size - window.size)/2 and only recomputes on contentItem
//   geometry changes, but Dialog resizes its contentItem before its window
//   (syncToMainItemSize()). Every Overlay-hosted Popup (AmpListOverlay,
//   SourceListOverlay) then renders shifted and press-outside-to-close is
//   dead outside the shifted rect. fixOverlay() resets it to (0,0)
//   whenever the window's size or visibility changes.
//
// - Sizing: Dialog takes its size from mainItem at show and afterwards
//   follows only the Layout.minimum*/maximum* hints, not implicit size.
//   The four equal hints below are both the sizing mechanism and the
//   no-resize pin. Never bind them to 0, unset or zero them while the
//   Dialog is shown: that kills plasmashell with a fatal Wayland protocol
//   error. They are bound to the content's implicit size, which is never 0
//   once FlyoutContent has loaded.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons

PlasmaCore.Dialog {
    id: flyoutPopup

    // Named `flyoutVisualParent` so it does not shadow Dialog's own
    // `visualParent`, which is bound to panelSpan (see header).
    required property Item flyoutVisualParent
    required property PlasmoidItem plasmoidItem
    // Root-anchored shared state, forwarded to FlyoutContent
    // (docs/DESIGN.md §3).
    required property PendingAmpState pendingAmpState
    required property VolumeSettings volumeSettings
    required property TransparencySettings transparencySettings
    required property ThemeSettings themeSettings

    // Window-derived types default to visible:true; without this the
    // popup opens on plasmashell startup. Initial value only, not a
    // binding: CompactRepresentation.qml's onClicked reassigns it.
    visible: false

    type: PlasmaCore.Dialog.AppletPopup
    backgroundHints: PlasmaCore.Dialog.NoBackground
    location: Plasmoid.location
    hideOnWindowDeactivate: flyoutPopup.plasmoidItem.hideOnWindowDeactivate
    visualParent: panelSpan

    onVisibleChanged: {
        if (flyoutPopup.visible) {
            console.log("[FlyoutPopup] opening - about to call requestActivate()");
            // Same call as CompactApplet.qml's own dialog makes on open.
            flyoutPopup.requestActivate();
        } else {
            console.log("[FlyoutPopup] closed");
        }
    }

    // Panel-edge anchor for Dialog::popupPosition() - see header. Declared
    // here (so this file owns the whole positioning story) but reparented
    // into the panel scene, as a child of the icon item, so that
    // mapRectToScene()/window() inside popupPosition() resolve against the
    // panel window. Invisible and never painted or hit-tested; geometry is
    // all it contributes.
    Item {
        id: panelSpan
        objectName: "flyoutPanelSpan"
        parent: flyoutPopup.flyoutVisualParent
        visible: false
        enabled: false

        // Which axis runs along the panel. Floating/Desktop (no edge) is
        // treated as horizontal, matching popupPosition()'s own default
        // branch (topPoint, i.e. bottom-edge behaviour).
        readonly property bool alongX: Plasmoid.location !== PlasmaCore.Types.LeftEdge
                                    && Plasmoid.location !== PlasmaCore.Types.RightEdge

        // The icon item's origin in its window, as a live binding: QML
        // tracks every `x`, `y` and `parent` read inside this loop, so a
        // panel re-layout that moves the applet re-evaluates it. (Item.
        // mapToItem() would give the same number but is not reactive.)
        readonly property point iconOrigin: {
            let x = 0, y = 0;
            for (let i = flyoutPopup.flyoutVisualParent; i; i = i.parent) {
                x += i.x;
                y += i.y;
            }
            return Qt.point(x, y);
        }

        // +1 on the far side only: popupPosition() reads the anchor's
        // far edge through QRect::bottom()/right(), which are inclusive
        // (top + height - 1), so an exact span lands the popup 1px inside
        // the panel (measured: y=35 on a 36px panel). The near edges use
        // top()/left() and need no correction. Window.* is the panel
        // window's size: the attached property follows this item's real
        // window after the reparent.
        x: alongX ? 0 : -iconOrigin.x
        y: alongX ? -iconOrigin.y : 0
        width: alongX ? (parent ? parent.width : 0) : Window.width + 1
        height: alongX ? Window.height + 1 : (parent ? parent.height : 0)
    }

    // It's a MouseEventListener to get all the events, matching
    // CompactApplet.qml's own comment on why (so the eventfilter can
    // catch them).
    mainItem: MouseEventListener {
        id: flyoutMainItem
        focus: true

        // QTBUG-146992 workaround, same as CompactApplet.qml's mainItem.
        enabled: flyoutPopup.visible

        // Content-driven size. No binding loop: FlyoutContent's implicit
        // sizes (theme.panelWidth, mainColumn.implicitHeight) don't depend
        // on its own width/height.
        implicitWidth: flyoutContent.implicitWidth
        implicitHeight: flyoutContent.implicitHeight

        // Sizing mechanism and no-resize pin (see header, "Sizing").
        // Never zero these while shown: it crashes plasmashell.
        Layout.minimumWidth: flyoutContent.implicitWidth
        Layout.maximumWidth: flyoutContent.implicitWidth
        Layout.minimumHeight: flyoutContent.implicitHeight
        Layout.maximumHeight: flyoutContent.implicitHeight

        // Qt 6.11 QQuickOverlay placement bug workaround - see header
        // ("Overlay.overlay reset"). Overlay.overlay here is this window's
        // overlay (mainItem lives in the Dialog window).
        function fixOverlay(reason) {
            const ov = Overlay.overlay;
            if (!ov) {
                return;
            }
            if (ov.x !== 0 || ov.y !== 0) {
                console.log("[FlyoutPopup] overlay offset", ov.x, ov.y, "(" + reason + ") -> reset to 0,0");
                ov.x = 0;
                ov.y = 0;
            }
        }
        Connections {
            target: flyoutPopup
            function onWidthChanged() { flyoutMainItem.fixOverlay("width " + flyoutPopup.width); }
            function onHeightChanged() { flyoutMainItem.fixOverlay("height " + flyoutPopup.height); }
            function onVisibleChanged() { flyoutMainItem.fixOverlay("visible " + flyoutPopup.visible); }
        }

        Keys.onEscapePressed: flyoutPopup.visible = false

        // A QtQuick.Controls Popup reparents its content into the
        // window's Overlay.overlay, a sibling of mainItem, so
        // Keys.onEscapePressed never sees Escape while focus is in an open
        // overlay. This window-scoped Shortcut does: the first press
        // closes the overlay, the second the window.
        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            enabled: flyoutPopup.visible
            onActivated: flyoutPopup.visible = false
        }

        // Relay focus into the real flyout content - the same
        // MouseEventListener -> content relay CompactApplet.qml uses to
        // hand focus to fullRepresentation.
        onActiveFocusChanged: {
            console.log("[FlyoutPopup] mainItem activeFocus:", flyoutMainItem.activeFocus);
            if (flyoutMainItem.activeFocus) {
                flyoutContent.forceActiveFocus();
            }
        }

        // Harness probe: non-visual; drives popup visibility and logs
        // every item's coordinates only while tools/flyout-harness/ is
        // running. It reads x/y/width/height/visible/active off `popup`.
        LayoutProbe {
            popup: flyoutPopup
            root: flyoutMainItem
            uiTarget: flyoutContent
        }

        // With NoBackground, FlyoutContent's own tint Rectangle is the
        // flyout's entire visible surface, edge to edge.
        FlyoutContent {
            id: flyoutContent
            anchors.fill: parent
            plasmoidItem: flyoutPopup.plasmoidItem
            pendingAmpState: flyoutPopup.pendingAmpState
            volumeSettings: flyoutPopup.volumeSettings
            transparencySettings: flyoutPopup.transparencySettings
            themeSettings: flyoutPopup.themeSettings
            popupVisible: flyoutPopup.visible
        }
    }
}
