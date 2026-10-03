// Phase 4.4.1: reusable copper pill switch, matching the mockup's
// .kcm-switch exactly (36x21 pill, surface3/divider when off, copperDim
// when on; 16x16 thumb sliding via translateX(15) and recoloring
// #e8e6e1 -> copperBright). Not a QQC2 Switch - its default style doesn't
// match this custom look, same reasoning as every other custom-drawn
// control in this project (mute/power buttons, volume slider).
//
// Phase 10.1.2: stateless, like DbStepper.qml - a click emits
// `toggled(newValue)` and the caller stores it (`checked: root.cfg_x;
// onToggled: (c) => root.cfg_x = c`). It used to write `checked =
// !checked` itself, which is an imperative assignment and therefore
// silently *broke* the caller's `checked: root.cfg_x` binding on the
// first click: from then on a write to cfg_x from anywhere else (the
// Defaults button, the shell pushing a stored value in) changed the
// value but not the switch. Found by the Phase 10.1.2 driver run on the
// chime toggle (Defaults reset cfg_chimeEnabled to true, switch stayed
// off); the Transparency toggle had the same latent defect since 9.1.0.
//
// Phase 11.0.0: a disabled look (opacity 0.4, ChimeIconButton.qml's own
// value) for the Launch at login switch while systemd is being queried
// or reports a state the toggle can't act on. Item.enabled already
// propagates to the MouseArea, so a disabled switch ignores clicks
// without any extra guard.
import QtQuick
import QtQuick.Effects
import "../ui" as Ui

Item {
    id: root

    property bool checked: false
    signal toggled(bool checked)
    readonly property Ui.Theme theme: Ui.Theme {}
    // Phase 17.14.0: the page's palette, forwarded by ConfigGeneral (one
    // palette for the whole page; required, so a missed hand-off fails at
    // load instead of silently painting a different palette).
    required property Ui.ColorPalette colors

    implicitWidth: 36
    implicitHeight: 21
    opacity: enabled ? 1.0 : 0.4

    // Phase 17.27.0: every colour from the palette's switch* tokens (dark:
    // the values this file painted before). In light the "on" track is a
    // gold sweep with a soft sheen and the knob is white with a shadow
    // (configDialog mockup v30 :76-77, :91-93, :276-286).
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked && !root.colors.isLight ? root.colors.switchOnStart : root.colors.switchOff
        border.width: 1
        border.color: root.colors.switchBorder
        Behavior on color { ColorAnimation { duration: 180 } }

        // Light "on" track, inside the border, faded in where dark
        // animates the colour.
        Item {
            anchors.fill: parent
            anchors.margins: 1
            visible: root.colors.isLight
            opacity: root.checked ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.colors.switchOnStart }
                    GradientStop { position: 0.6; color: root.colors.switchOnMid }
                    GradientStop { position: 1.0; color: root.colors.switchOnEnd }
                }
            }
            // linear-gradient(180deg, rgba(255,255,255,0.28) 0%, transparent 60%)
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.28) }
                    GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
        }
    }

    // --knob-shadow: 0 1px 3px (light only).
    RectangularShadow {
        visible: root.colors.isLight
        x: knob.x
        y: knob.y
        width: knob.width
        height: knob.height
        radius: knob.radius
        offset.y: 1
        blur: 3
        color: root.colors.switchKnobShadow
    }

    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        y: 1.5
        x: root.checked ? root.width - width - 1.5 : 1.5
        color: root.checked ? root.colors.switchKnobOn : root.colors.switchKnobOff
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
