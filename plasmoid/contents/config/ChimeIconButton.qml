// The mockup's `.file-picker-btn` (v16 configDialog mockup, CSS lines
// 230-237): a 28x28 icon button for the Volume Feedback section's Preview
// (play) and Browse (folder) buttons.
//
// Hand-drawn like the page's other buttons (surface fill, border turning
// copperDim on hover); the qqc2-desktop-style Button does not match this
// page. Radius is theme.radiusSm (8) where the mockup says 7px, as in
// DbStepper.qml.
//
// Glyphs are the mockup's SVG path data verbatim, in its 24-unit viewBox,
// scaled to its 14px rendering size (`.file-picker-btn svg{width:14px}`).
//
// `playing` is the mockup's 350 ms `.playing` pulse (copper 0.18 fill + a
// 3px copperBright 0.18 ring), a click acknowledgement only; the caller
// plays the sound on `clicked`.
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import "../ui" as Ui

Item {
    id: root

    // "play" (filled triangle, copper at rest) or "browse" (folder outline,
    // dim at rest, copper on hover) - the mockup's `.play` modifier class.
    property string kind: "play"
    property string tooltip: ""
    property bool playing: false

    signal clicked()

    readonly property Ui.Theme theme: Ui.Theme {}
    // The page's palette, forwarded by ConfigGeneral (required, so a
    // missed hand-off fails at load).
    required property Ui.ColorPalette colors
    readonly property bool isPlay: root.kind === "play"
    readonly property bool hot: root.isPlay || area.containsMouse

    implicitWidth: 28
    implicitHeight: 28
    // Disabled dim (as in DbStepper.qml): the only signal that Preview has
    // nothing to play yet (no file picked, or no theme with an
    // audio-volume-change.oga found).
    opacity: enabled ? 1.0 : 0.4

    // `.playing` box-shadow ring: 3px outside the button's own edge.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: root.theme.radiusSm + 3
        color: Qt.rgba(root.colors.copperBright.r, root.colors.copperBright.g, root.colors.copperBright.b, 0.18)
        visible: root.playing
    }

    Rectangle {
        anchors.fill: parent
        radius: root.theme.radiusSm
        color: root.playing
            ? Qt.rgba(root.colors.copper.r, root.colors.copper.g, root.colors.copper.b, 0.18)
            : root.colors.surface
        border.width: 1
        border.color: root.hot ? root.colors.copperDim : root.colors.controlBorder
        // Light-theme card shadow.
        Ui.CardShadow { colors: root.colors; radius: parent.radius; visible: root.colors.isLight && !root.playing }

        Shape {
            id: glyph
            anchors.centerIn: parent
            width: 24
            height: 24
            scale: 14 / 24
            readonly property color tint: root.hot ? root.colors.copperBright : root.colors.textDim

            // Mockup line 501/522/536: <path d="M8 6.5v11l9-5.5-9-5.5z"/>
            // (fill="currentColor", stroke="none").
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: root.isPlay ? glyph.tint : "transparent"
                PathSvg { path: "M8 6.5v11l9-5.5-9-5.5z" }
            }

            // Mockup line 533: the folder outline (fill="none",
            // stroke="currentColor", stroke-width="2", round cap/join).
            ShapePath {
                strokeWidth: 2
                strokeColor: root.isPlay ? "transparent" : glyph.tint
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z" }
            }
        }
    }

    Timer {
        id: pulse
        interval: 350
        onTriggered: root.playing = false
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (root.isPlay) {
                root.playing = true;
                pulse.restart();
            }
            root.clicked();
        }
    }

    ToolTip.text: root.tooltip
    ToolTip.visible: root.tooltip !== "" && area.containsMouse
    ToolTip.delay: 500
}
