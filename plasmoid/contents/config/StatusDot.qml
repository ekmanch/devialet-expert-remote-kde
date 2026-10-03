// Phase 17.25.0 - the 6 px dot in front of the settings page's status
// lines ("Following your desktop's ..."): flat copperBright in dark, the
// gold sphere in light (configDialog mockup v30 `--dot-bg`, :89), the same
// treatment as the flyout's status dots.

pragma ComponentBehavior: Bound

import QtQuick
import "../ui" as Ui

Rectangle {
    id: dot

    required property Ui.ColorPalette colors

    implicitWidth: 6
    implicitHeight: 6
    radius: 3
    color: dot.colors.isLight ? "transparent" : dot.colors.copperBright

    Loader {
        anchors.centerIn: parent
        active: dot.colors.isLight
        sourceComponent: Ui.GoldSphere {
            diameter: 6
            shadowVerticalOffset: 1
            shadowBlur: 0.25
        }
    }
}
