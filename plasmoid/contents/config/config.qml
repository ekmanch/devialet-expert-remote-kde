// Adds our "General" category to the ConfigDialog Plasma already provides
// for every applet (Keyboard Shortcuts and About come from the shell and
// cannot be removed; ours is listed first and opens by default). Found by
// its fixed path; no metadata.json key is involved. See docs/DESIGN.md §4.
//
// `ConfigCategory.source` resolves relative to `contents/ui/`, not to this
// file, for bare strings and Qt.resolvedUrl() alike. Our pages live in
// `contents/config/`, hence `"../config/ConfigGeneral.qml"`. A wrong path
// surfaces as a Kirigami PageRow "Could not convert argument 1 ... to
// QQuickItem*" error that breaks page navigation for the whole session.

import QtQuick
import org.kde.plasma.configuration

import org.kde.plasma.configuration

// White icon on a dark sidebar, the dark-ink copy (stroke #1c1a17) on a
// light one. Read from SystemPalette's window colour, not SystemScheme.qml
// like the page: it must be right when the sidebar first reads it (the
// portal reply arrives later), and a ConfigModel is not an Item, so
// Kirigami's attached Theme is unavailable. The portal's color-scheme is
// computed from the same window colour.
//
// `icon` is a plain string passed unresolved to the shell's sidebar
// delegate (`Kirigami.Icon { source: model.icon }`), which would resolve a
// relative path against its own package and show a broken image. So it is
// made absolute here with Qt.resolvedUrl(). The icon is a bundled SVG;
// Keyboard Shortcuts' and About's icons are hardcoded in the shell and
// cannot be matched.
ConfigModel {
    id: configModel

    readonly property SystemPalette systemPalette: SystemPalette {}
    readonly property bool darkWindow: configModel.systemPalette.window.hslLightness < 0.5

    ConfigCategory {
        name: i18n("General")
        icon: Qt.resolvedUrl(configModel.darkWindow
            ? "../icons/devialet_config_general_icon_white.svg"
            : "../icons/devialet_config_general_icon_dark.svg")
        source: "../config/ConfigGeneral.qml"
    }
}
