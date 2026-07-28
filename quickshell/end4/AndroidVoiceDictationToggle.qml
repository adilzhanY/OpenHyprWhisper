// Android-style quick toggle button for OpenHyprWhisper.
// Install to: ~/.config/quickshell/ii/modules/ii/sidebarRight/quickToggles/androidStyle/
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

AndroidQuickToggleButton {
    toggleModel: VoiceDictationToggle {}
}
