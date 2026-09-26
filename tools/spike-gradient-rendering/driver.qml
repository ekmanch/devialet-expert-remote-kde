// Spike driver: renders every question on one white sheet and grabs it at
// the window's device pixel ratio (2 on the owner's screen / QT_SCALE_FACTOR=2
// offscreen). Row bands are at fixed y so zoom.py can crop them blind.
import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: win
    width: 640
    height: 360
    visible: true
    color: "#ffffff"
    flags: Qt.FramelessWindowHint
    title: "spike-gradient-rendering"

    FontLoader { id: jbMedium; source: "../../plasmoid/contents/fonts/jetbrains_mono_medium.ttf" }
    FontLoader { id: jbRegular; source: "../../plasmoid/contents/fonts/jetbrains_mono_regular.ttf" }
    FontLoader { id: sgSemibold; source: "../../plasmoid/contents/fonts/space_grotesk_semibold.ttf" }
    FontLoader { id: sgBold; source: "../../plasmoid/contents/fonts/space_grotesk_bold.ttf" }

    component Tag: Label { font.pixelSize: 8; color: "#000000"; font.family: "sans-serif" }
    component Unit: Label { text: "dB"; font.family: jbRegular.name; font.pixelSize: 12; color: "#6e6a64" }

    // ---- Row 1 (y 16-76): readout 26px, two-stage glow strengths ------
    Tag { x: 8; y: 6; text: "R1 readout 26px two-stage: glow blur 0.35/32 | 0.6/32 | 0.9/32 | 0.6/64 | mask only | plain #1c1a17" }
    Row {
        x: 16; y: 20; spacing: 18
        GradientText { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 26; font.weight: Font.Medium; glow: true; glowBlur: 0.35; glowBlurMax: 32 }
        GradientText { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 26; font.weight: Font.Medium; glow: true; glowBlur: 0.6; glowBlurMax: 32 }
        GradientText { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 26; font.weight: Font.Medium; glow: true; glowBlur: 0.9; glowBlurMax: 32 }
        GradientText { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 26; font.weight: Font.Medium; glow: true; glowBlur: 0.6; glowBlurMax: 64 }
        GradientText { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 26; font.weight: Font.Medium }
        Label { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 26; font.weight: Font.Medium; color: "#1c1a17" }
    }

    // ---- Row 2 (y 90-130): small gradient text ------------------------
    Tag { x: 8; y: 80; text: "R2 small: OSD 15px+glow | tooltip 13px+glow | heading 11px | status 'Light' 11px bold | OSD 'Muted' 12px bold | plain 11px ref" }
    Row {
        x: 16; y: 96; spacing: 22
        GradientText { text: "−22.0"; font.family: jbMedium.name; font.pixelSize: 15; font.weight: Font.Medium; glow: true; glowBlur: 0.35 }
        GradientText { text: "−25.0"; font.family: jbMedium.name; font.pixelSize: 13; font.weight: Font.Medium; glow: true; glowBlur: 0.3 }
        GradientText { text: "APPEARANCE"; font.family: sgSemibold.name; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.4
            stop0Color: "#a8710b"; stop1Color: "#d99a1f"; stop1Pos: 0.55; stop2Color: "#efc36a" }
        GradientText { text: "Light"; font.family: jbMedium.name; font.pixelSize: 11; font.weight: Font.Bold
            stop0Color: "#a8710b"; stop1Color: "#d99a1f"; stop1Pos: 0.55; stop2Color: "#efc36a" }
        GradientText { text: "Muted"; font.family: sgBold.name; font.pixelSize: 12; font.weight: Font.Bold
            stop0Color: "#a8710b"; stop1Color: "#d99a1f"; stop1Pos: 0.55; stop2Color: "#efc36a" }
        Label { text: "APPEARANCE"; font.family: sgSemibold.name; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.4; color: "#9c6d20" }
    }

    // ---- Row 3 (y 150-190): spheres -----------------------------------
    Tag { x: 8; y: 138; text: "R3 spheres: thumb 14 (halo 3, shadow 0 1 3) | 12 | 10 | 7 | 6 (shadow 0 2 2.5) | flat #e3a06a 12 ref | 12 no shadow" }
    Row {
        x: 24; y: 156; spacing: 26
        GoldSphere { diameter: 14; haloWidth: 3; shadowVerticalOffset: 1; shadowBlur: 0.35; shadowColor: "#6e480a" }
        GoldSphere { diameter: 12 }
        GoldSphere { diameter: 10 }
        GoldSphere { diameter: 7 }
        GoldSphere { diameter: 6 }
        Rectangle { width: 12; height: 12; radius: 6; color: "#e3a06a" }
        GoldSphere { diameter: 12; shadowEnabled: false }
    }

    // ---- Row 4 (y 210-250): glyphs (two-stage) ------------------------
    Tag { x: 8; y: 198; text: "R4 glyphs: optical 20 flat copper | optical 20 gold+shadow | airplay 20 gold+shadow | optical 17 gold+shadow | airplay 17 gold+shadow | optical 17 flat" }
    Row {
        x: 24; y: 214; spacing: 30
        GlyphShape { kind: "optical"; size: 20; color: "#c17f4e" }
        Item { width: 20; height: 20
            GlyphShape { id: g1; anchors.fill: parent; kind: "optical"; size: 20; color: "black"; visible: false; layer.enabled: true }
            GradientMask { anchors.fill: parent; maskSource: g1; radial: true; radialCenterX: 6.4; radialCenterY: 5.6; radialRadius: 15.5; shadowEnabled: true } }
        Item { width: 20; height: 20
            GlyphShape { id: g2; anchors.fill: parent; kind: "airplay"; size: 20; color: "black"; visible: false; layer.enabled: true }
            GradientMask { anchors.fill: parent; maskSource: g2; radial: true; radialCenterX: 6.4; radialCenterY: 5.6; radialRadius: 15.5; shadowEnabled: true } }
        Item { width: 17; height: 17
            GlyphShape { id: g3; anchors.fill: parent; kind: "optical"; size: 17; color: "black"; visible: false; layer.enabled: true }
            GradientMask { anchors.fill: parent; maskSource: g3; radial: true; radialCenterX: 6.4 * 0.85; radialCenterY: 5.6 * 0.85; radialRadius: 15.5 * 0.85; shadowEnabled: true } }
        Item { width: 17; height: 17
            GlyphShape { id: g4; anchors.fill: parent; kind: "airplay"; size: 17; color: "black"; visible: false; layer.enabled: true }
            GradientMask { anchors.fill: parent; maskSource: g4; radial: true; radialCenterX: 6.4 * 0.85; radialCenterY: 5.6 * 0.85; radialRadius: 15.5 * 0.85; shadowEnabled: true } }
        GlyphShape { kind: "optical"; size: 17; color: "#c17f4e" }
    }

    // ---- Row 5 (y 270-310): speaker SVGs ------------------------------
    Tag { x: 8; y: 258; text: "R5 speaker svg 17px (two-stage): muted gold+shadow (plain Image mask) | waves gold+shadow | muted plain black (Image) | muted gold via layer-enabled Image" }
    Row {
        x: 24; y: 274; spacing: 30
        Item { width: 17; height: 17
            Image { id: s1; anchors.fill: parent; source: "speaker-muted.svg"; sourceSize: Qt.size(17, 17); visible: false }
            GradientMask { anchors.fill: parent; maskSource: s1; radial: true
                radialCenterX: 6.4 * 0.85; radialCenterY: 5.6 * 0.85; radialRadius: 15.5 * 0.85; shadowEnabled: true } }
        Item { width: 17; height: 17
            Image { id: s2; anchors.fill: parent; source: "speaker-waves.svg"; sourceSize: Qt.size(17, 17); visible: false }
            GradientMask { anchors.fill: parent; maskSource: s2; radial: true
                radialCenterX: 6.4 * 0.85; radialCenterY: 5.6 * 0.85; radialRadius: 15.5 * 0.85; shadowEnabled: true } }
        Image { width: 17; height: 17; source: "speaker-muted.svg"; sourceSize: Qt.size(17, 17) }
        Item { width: 17; height: 17
            Image { id: s4; anchors.fill: parent; source: "speaker-muted.svg"; sourceSize: Qt.size(17, 17); visible: false; layer.enabled: true }
            GradientMask { anchors.fill: parent; maskSource: s4; radial: true
                radialCenterX: 6.4 * 0.85; radialCenterY: 5.6 * 0.85; radialRadius: 15.5 * 0.85; shadowEnabled: true } }
    }

    Tag { x: 8; y: 330; text: "dpr " + Screen.devicePixelRatio + "  fonts: " + jbMedium.name + " / " + sgSemibold.name }

    Timer {
        interval: 1200; running: true; repeat: false
        onTriggered: {
            const dpr = Screen.devicePixelRatio;
            const api = win.contentItem.GraphicsInfo.api;
            win.contentItem.grabToImage(function (result) {
                const ok = result.saveToFile("captures/sheet.png");
                console.warn("[spike] grabbed dpr", dpr, "saved", ok, "graphics api", api,
                             "(Software=" + GraphicsInfo.Software + " OpenGL=" + GraphicsInfo.OpenGL + " Vulkan=" + GraphicsInfo.Vulkan + ")",
                             "fonts", jbMedium.name, sgSemibold.name, "status", jbMedium.status, sgSemibold.status);
                Qt.quit();
            });
        }
    }
}
