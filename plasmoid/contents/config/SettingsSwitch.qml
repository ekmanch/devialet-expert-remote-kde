// Pill switch, the mockup's .kcm-switch (36x21 pill, 16x16 knob). Not a
// QQC2 Switch: its default style does not match this look.
//
// Stateless, like DbStepper.qml: a click emits `toggled(newValue)` and the
// caller stores it (`checked: root.cfg_x; onToggled: (c) => root.cfg_x =
// c`). Writing `checked` here would break the caller's binding, so a later
// write to cfg_x (Defaults, the shell loading a stored value) would no
// longer move the switch.
//
// Disabled look is opacity 0.4 (Launch at login while systemd is being
// queried or reports a state the toggle can't act on). Item.enabled
// propagates to the MouseArea, so a disabled switch ignores clicks.
import QtQuick
import QtQuick.Effects
import "../ui" as Ui

Item {
    id: root

    property bool checked: false
    signal toggled(bool checked)
    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded by ConfigGeneral (required, so a
    // missed hand-off fails at load).
    required property Ui.ColorPalette colors

    implicitWidth: 36
    implicitHeight: 21
    opacity: enabled ? 1.0 : 0.4

    // Every colour comes from the palette's switch* tokens. In light the
    // "on" track is a gold sweep with a soft sheen and the knob is white
    // with a shadow (configDialog mockup v30 :76-77, :91-93, :276-286).
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
