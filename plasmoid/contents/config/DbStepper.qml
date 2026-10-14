// Numeric dB +/- stepper for the Volume Limits and startup-volume rows
// (the configDialog mockup's .db-stepper).
//
// Hold-to-repeat uses Button's own autoRepeat. Delay/interval (300/100 ms)
// and the button shape (26x26, surface fill, copperDim hover border) match
// VolumeBlock.qml's flyout volume buttons, not the mockup's placeholder
// 400/100 ms.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../ui" as Ui

RowLayout {
    id: root

    property real value: 0
    property real from: -96
    property real to: 0
    property real stepDb: 1

    // Emitted on every step (click or autoRepeat tick) with the new,
    // already-clamped value. Stateless: the caller stores it (e.g. into a
    // cfg_* property) and writes `value` back.
    signal stepped(real value)

    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded by ConfigGeneral (required, so a
    // missed hand-off fails at load).
    required property Ui.ColorPalette colors

    spacing: 8

    function clamp(v) {
        return Math.max(root.from, Math.min(root.to, v));
    }

    Button {
        text: "−"
        enabled: root.value > root.from
        autoRepeat: true
        autoRepeatDelay: 300
        autoRepeatInterval: 100
        onClicked: root.stepped(root.clamp(root.value - root.stepDb))

        // Dimmed at the boundary (`from`/`to`; for the floor/hard-limit
        // pair, one step from the other stepper's value) so a click that
        // does nothing looks disabled. Per button, not per row: the other
        // button stays usable.
        implicitWidth: 26
        implicitHeight: 26
        opacity: enabled ? 1.0 : 0.4
        background: Rectangle {
            radius: root.theme.radiusSm
            color: root.colors.surface
            border.width: 1
            border.color: parent.hovered ? root.colors.copperDim : root.colors.controlBorder
            // Light-theme card shadow.
            Ui.CardShadow { colors: root.colors; radius: parent.radius }
        }
        contentItem: Label {
            text: parent.text
            font.family: root.theme.fontDisplay
            font.weight: Font.DemiBold
            font.pixelSize: 14
            color: parent.hovered ? root.colors.copperBright : root.colors.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        radius: root.theme.radiusSm
        color: root.colors.surface
        border.width: 1
        border.color: root.colors.controlBorder
        // Light-theme card shadow (`--val-shadow`).
        Ui.CardShadow { colors: root.colors; radius: parent.radius }
        implicitWidth: valueLabel.implicitWidth + 20
        implicitHeight: 26

        Label {
            id: valueLabel
            anchors.centerIn: parent
            text: Math.round(root.value) + " dB"
            font.family: root.theme.fontMono
            font.pixelSize: 12
            // Neutral in light (configDialog mockup v30 :107).
            color: root.colors.controlValueText
            wrapMode: Text.NoWrap
        }
    }

    Button {
        text: "+"
        enabled: root.value < root.to
        autoRepeat: true
        autoRepeatDelay: 300
        autoRepeatInterval: 100
        onClicked: root.stepped(root.clamp(root.value + root.stepDb))

        implicitWidth: 26
        implicitHeight: 26
        opacity: enabled ? 1.0 : 0.4
        background: Rectangle {
            radius: root.theme.radiusSm
            color: root.colors.surface
            border.width: 1
            border.color: parent.hovered ? root.colors.copperDim : root.colors.controlBorder
            // Light-theme card shadow.
            Ui.CardShadow { colors: root.colors; radius: parent.radius }
        }
        contentItem: Label {
            text: parent.text
            font.family: root.theme.fontDisplay
            font.weight: Font.DemiBold
            font.pixelSize: 14
            color: parent.hovered ? root.colors.copperBright : root.colors.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
