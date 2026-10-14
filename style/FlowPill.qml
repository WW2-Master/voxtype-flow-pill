import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: root

    // Voxtype's supported custom-style interface.
    property string daemonState: "idle"
    property var audio: null
    property var theme: null
    property var recipe: null
    property string assetRoot: ""
    readonly property Item inputItem: pill
    readonly property bool active: daemonState !== "idle" && daemonState !== ""
    readonly property bool listening: daemonState === "recording" || daemonState === "streaming"

    // The public Flow Bar's 96.5 x 28 proportions, slightly enlarged for
    // comfortable desktop use. Its colors stay neutral across theme changes.
    property real uiScale: 1.2
    property real reveal: active ? 1 : 0
    property real phase: 0
    property real lastTick: Date.now()
    property real lastFrame: 0
    property var history: []
    property var levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    readonly property var weights: [0.35, 0.65, 0.50, 0.85, 0.70, 1.0, 0.85, 0.50, 0.40, 0.25]

    function setting(key, fallback) {
        return theme && theme.config && theme.config[key] !== undefined
            ? theme.config[key] : fallback;
    }

    function resetAudio() {
        history = [];
        levels = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        lastFrame = 0;
    }

    function audioLevel(peak, rms) {
        const energy = Math.max(0, rms * 0.75 + peak * 0.25 - 0.003);
        // Compress the microphone's full dynamic range smoothly. Multiplying
        // by 10 and clipping at 1 flattened ordinary speech to one height.
        return Math.min(1, Math.log(1 + energy * 6) / Math.log(7));
    }

    onDaemonStateChanged: {
        if (daemonState !== "recording" && daemonState !== "streaming") resetAudio();
        lastTick = Date.now();
    }
    Behavior on reveal { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

    Connections {
        target: root.audio
        enabled: root.audio !== null
        function onFrameReceived(peak, rms, vad, tsMs) {
            if (!root.listening) return;
            // Short rolling window, driven by real sound rather than VAD:
            // this also works when Voxtype's voice detection is disabled.
            const next = root.history.slice();
            next.push(root.audioLevel(peak, rms));
            while (next.length > 40) next.shift();
            root.history = next;
            root.lastFrame = Date.now();
        }
        function onDisconnected() { root.resetAudio(); }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.active || root.reveal > 0
        onTriggered: {
            const now = Date.now();
            const dt = Math.min(0.05, Math.max(0.001, (now - root.lastTick) / 1000));
            root.lastTick = now;
            root.phase += dt;
            const next = [];
            for (let i = 0; i < 10; i++) {
                let target = 0;
                if (root.listening && now - root.lastFrame < 150) {
                    const end = root.history.length - (9 - i) * 3;
                    let sum = 0;
                    let count = 0;
                    for (let j = Math.max(0, end - 4); j < end; j++) {
                        sum += root.history[j];
                        count++;
                    }
                    target = count ? sum / count * root.weights[i] : 0;
                }
                const current = root.levels[i];
                // Fast attack, soft release: lively speech, steady silence.
                const speed = target > current ? 24 : 12;
                next.push(current + (target - current) * (1 - Math.exp(-speed * dt)));
            }
            root.levels = next;
        }
    }

    Rectangle {
        id: shadowSource
        visible: false
        width: pill.width
        height: pill.height
        radius: pill.radius
        color: "#000000"
    }
    MultiEffect {
        anchors.centerIn: pill
        width: pill.width
        height: pill.height
        source: shadowSource
        opacity: pill.opacity
        scale: pill.scale
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.24
        shadowBlur: 0.6
        shadowVerticalOffset: 3
        blurMax: 24
        autoPaddingEnabled: true
    }

    Rectangle {
        id: pill
        readonly property real unit: root.uiScale
        readonly property string position: String(root.setting("position", "bottom-center"))
        readonly property real margin: Math.max(0, Number(root.setting("margin_px", 48)))
        width: 96.5 * unit
        height: 28 * unit
        radius: 14 * unit
        color: "#1A1A1A"
        border.width: 1
        border.color: "#4D4A42"
        x: position.indexOf("left") >= 0 ? margin
           : position.indexOf("right") >= 0 ? root.width - width - margin
           : (root.width - width) / 2
        y: (position.indexOf("top") === 0 ? margin : root.height - height - margin)
           + 5 * (1 - root.reveal)
        opacity: root.reveal
        scale: 0.94 + 0.06 * root.reveal

        Rectangle {
            id: cancelButton
            x: 6 * pill.unit
            y: 5 * pill.unit
            width: 18 * pill.unit
            height: width
            radius: width / 2
            color: cancelMouse.containsMouse ? "#90908C" : "#71716E"
            Behavior on color { ColorAnimation { duration: 90 } }
            Canvas {
                anchors.centerIn: parent
                width: 12 * pill.unit
                height: width
                antialiasing: true
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.scale(pill.unit, pill.unit);
                    ctx.strokeStyle = "#FCFCFB";
                    ctx.lineWidth = 1.5;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.moveTo(9, 3); ctx.lineTo(3, 9);
                    ctx.moveTo(3, 3); ctx.lineTo(9, 9);
                    ctx.stroke();
                }
            }
            MouseArea {
                id: cancelMouse
                anchors.fill: parent
                anchors.margins: -3 * pill.unit
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.active
                onClicked: Quickshell.execDetached(["voxtype", "record", "cancel"])
            }
        }

        Item {
            x: 28 * pill.unit
            y: 5 * pill.unit
            width: 40.5 * pill.unit
            height: 18 * pill.unit
            Repeater {
                model: 10
                Rectangle {
                    required property int index
                    x: index * 4.25 * pill.unit
                    width: 2.25 * pill.unit
                    height: (2.25 + 14 * root.levels[index]) * pill.unit
                    anchors.verticalCenter: parent.verticalCenter
                    radius: width / 2
                    color: "#FFFFEB"
                    opacity: root.listening ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 4 * pill.unit
                opacity: root.listening ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 3 * pill.unit
                        height: width
                        radius: width / 2
                        color: "#FFFFEB"
                        opacity: 0.3 + 0.7 * Math.pow((Math.sin(root.phase * 6 - index * 0.85) + 1) / 2, 2)
                        transform: Translate { y: -2 * pill.unit * Math.sin(root.phase * 6 - index * 0.85) }
                    }
                }
            }
        }

        Rectangle {
            id: finishButton
            x: 72.5 * pill.unit
            y: 5 * pill.unit
            width: 18 * pill.unit
            height: width
            radius: width / 2
            color: finishMouse.containsMouse ? "#E2E2DB" : "#FCFCFB"
            opacity: root.listening ? 1 : 0.3
            Behavior on color { ColorAnimation { duration: 90 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Canvas {
                anchors.centerIn: parent
                width: 12 * pill.unit
                height: width
                antialiasing: true
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.scale(pill.unit, pill.unit);
                    ctx.strokeStyle = "#1A1A1A";
                    ctx.lineWidth = 1.5;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    ctx.moveTo(10, 3); ctx.lineTo(4.5, 8.5); ctx.lineTo(2, 6);
                    ctx.stroke();
                }
            }
            MouseArea {
                id: finishMouse
                anchors.fill: parent
                anchors.margins: -3 * pill.unit
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.listening
                onClicked: Quickshell.execDetached(["voxtype", "record", "stop"])
            }
        }
    }
}
