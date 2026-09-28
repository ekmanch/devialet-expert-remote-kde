// Phase 17.19.0 - the light theme's card shadow under a control (buttons,
// source row, volume chip, +/- steppers): flyout mockup v3 `--card-shadow:
// 0 2px 8px -3px rgba(20,16,10,0.10), 0 1px 2px rgba(20,16,10,0.05)`.
//
// Put it inside the control's background Rectangle; `z: -1` draws it under
// that Rectangle, and it follows the parent's size and radius. Hidden in the
// dark theme (whose cardShadow is transparent anyway).
//
// Like CSS box-shadow, nothing is painted under the control itself: the
// light controls are translucent (since Phase 17.19.2 `surface` at the
// palette's fixed controlAlphaK, see ColorPalette.controlColor()), and a
// shadow left under them shows through the whole face - measured in 17.19.0
// (then with 17.19.0's glass alpha) at 50 % opacity as a face 9 levels
// darker than intended (223 vs 232).
// So the shadows are drawn into a hidden layer `reach` px larger than the
// control on every side, and a MultiEffect with an inverted mask (the
// control's own rounded rect) cuts the control's area out of them. Two
// small textures per control, only while the light theme is shown.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: cs

    required property ColorPalette colors
    property real radius: 0

    // Blur 8 + offset 2 of the larger shadow, plus margin.
    readonly property real reach: 14

    anchors.fill: parent
    z: -1
    visible: cs.colors.isLight

    // Built only while shown, with the layers on from the start: a
    // MultiEffect whose source/mask layers were switched on after it was
    // created (a runtime dark -> light flip) kept drawing but stopped
    // cutting the mask - reproduced in a standalone driver (face 184 instead
    // of 192 over grey). Also means no textures at all in the dark theme.
    Loader {
        anchors.fill: parent
        active: cs.visible
        sourceComponent: Item {
            Item {
                id: shadows
                anchors.fill: parent
                anchors.margins: -cs.reach
                visible: false
                layer.enabled: true

                RectangularShadow {
                    x: cs.reach
                    y: cs.reach
                    width: cs.width
                    height: cs.height
                    radius: cs.radius
                    offset.y: 2
                    blur: 8
                    spread: -3
                    color: cs.colors.cardShadow
                }
                RectangularShadow {
                    x: cs.reach
                    y: cs.reach
                    width: cs.width
                    height: cs.height
                    radius: cs.radius
                    offset.y: 1
                    blur: 2
                    color: Qt.rgba(cs.colors.cardShadow.r, cs.colors.cardShadow.g, cs.colors.cardShadow.b, cs.colors.cardShadow.a / 2)
                }
            }

            Item {
                id: hole
                anchors.fill: shadows
                visible: false
                layer.enabled: true

                Rectangle {
                    x: cs.reach
                    y: cs.reach
                    width: cs.width
                    height: cs.height
                    radius: cs.radius
                    antialiasing: true
                    color: "black"
                }
            }

            MultiEffect {
                anchors.fill: shadows
                source: shadows
                autoPaddingEnabled: false
                maskEnabled: true
                maskInverted: true
                maskSource: hole
            }
        }
    }
}
