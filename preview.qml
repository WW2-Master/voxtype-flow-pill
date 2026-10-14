// Documentation preview with synthetic levels; it does not record audio.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "style" as Flow

ShellRoot {
    QtObject {
        id: demoAudio
        property real phase: 0
        signal frameReceived(real peak, real rms, bool vad, var tsMs)
        signal disconnected()
        property Timer frames: Timer {
            interval: 10
            running: true
            repeat: true
            onTriggered: {
                demoAudio.phase += 0.01;
                const level = Math.max(0, 0.24 + 0.14 * Math.sin(demoAudio.phase * 11)
                    + 0.08 * Math.sin(demoAudio.phase * 27));
                demoAudio.frameReceived(level * 1.6, level, true, Date.now());
            }
        }
    }
    PanelWindow {
        id: window
        implicitWidth: 260
        implicitHeight: 112
        anchors.bottom: true
        margins.bottom: 140
        color: "#111317"
        WlrLayershell.namespace: "voxtype-flow-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            intersection: Intersection.Subtract
            width: window.width
            height: window.height
        }
        Flow.FlowPill {
            anchors.fill: parent
            daemonState: "recording"
            audio: demoAudio
            theme: QtObject { property var config: ({ margin_px: 39 }) }
        }
    }
}
