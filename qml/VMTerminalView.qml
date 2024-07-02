import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import CppCustomModules 1.0

FocusScope {
    id: control

    signal closed()

    SshConnection {
        id: sshConnection
        active: control.enabled
        user: sshUser
        host: sshHost
        port: sshPort
        termType: sshTerm
        privateKey: sshKey
        checkServer: sshCheck
        onOpenChannelsChanged: function(channels) { if (!channels) control.closed() }
        onLastErrorChanged: connectingText.text += lastError + "\n\n"
        onRunningChanged: if (running) connectingText.text = ""

        // The following is not used in default shell mode when no command specified
        //onActiveChanged: print("active", active)
        //onConnectionChanged: print("connection", connection)
        //onExitSignalChanged: print("exitSignal", exitSignal)
        //onExitStatusChanged: print("exitStatus", exitStatus)
        //onStdOutputChanged: function(data) { print("output", data.toString()) }
        //onStdErrorChanged: function(data) { print("error", data.toString()) }
    }

    TextRender {
        id: textRender
        anchors.fill: parent
        focus: !isMobile
        secureShell: sshConnection
        dragMode: isMobile ? TextRender.DragScroll : TextRender.DragSelect

        property int cutAfter: height
        onCutAfterChanged: redraw()
        onDisplayBufferChanged: {
            cutAfter = height
            y = 0
        }
        onPanLeft:  putString(termPanLeft)
        onPanRight: putString(termPanRight)
        onPanUp:    putString(termPanUp)
        onPanDown:  putString(termPanDown)
        contentItem: Item {
            anchors.fill: parent
            Behavior on opacity { NumberAnimation { easing.type: Easing.InOutQuad }}
            Behavior on y { NumberAnimation { easing.type: Easing.InOutQuad }}
        }
        cellDelegate: Rectangle {}
        cellContentsDelegate: Text {
            id: text
            property bool blinking: false
            textFormat: Text.PlainText
            opacity: blinking ? 0.5 : 1.0
            SequentialAnimation {
                running: text.blinking
                loops: Animation.Infinite
                NumberAnimation { target: text; property: "opacity"; to: 0.8; duration: 200 }
                PauseAnimation { duration: 400 }
                NumberAnimation { target: text; property: "opacity"; to: 0.5; duration: 200 }
            }
        }
        cursorDelegate: Rectangle {
            id: cursor
            property bool blinking: termFadeCursor
            NumberAnimation on opacity {
                running: cursor.blinking && Qt.application.state === Qt.ApplicationActive
                loops: Animation.Infinite; from: 1.0; to: 0.3; duration: 1200
                onStopped: Qt.callLater(function() { cursor.opacity = 1.0 })
            }
        }
        selectionDelegate: Rectangle { opacity: 0.5; color: termSelection }
        onVisualBell: if (termVisualBell) bellTimer.start()
        Keys.onShortcutOverride: function(event) { event.accepted = event.matches(StandardKey.Cancel) }
    }

    Timer {
        id: bellTimer
        interval: 100
    }
    Rectangle {
        id: bellTimerRect
        anchors.fill: parent
        visible: opacity > 0
        opacity: bellTimer.running ? 0.5 : 0.0
        color: "white"
        Behavior on opacity { NumberAnimation {}}
    }

    ScrollIndicator {
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        orientation: Qt.Vertical
        hoverEnabled: true
        active: hovered || textRender.contentHeight > textRender.visibleHeight
        readonly property int maxHeight: Math.max(textRender.contentHeight, 1)
        size: textRender.visibleHeight / maxHeight
        position: textRender.contentY / maxHeight
    }

    Text {
        id: connectingText
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignHCenter
        visible: text
        font.family: appWindow.font.family
        font.pointSize: appExplainSize
        font.italic: true
        color: Material.accent
        wrapMode: Text.Wrap
        text: control.enabled ? qsTr("Connecting %1...").arg(sshConnection.host) + "\n\n" : qsTr("No terminal available")
    }
}
