import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15

import CppCustomModules 1.0
import QmlCustomModules 1.0

ApplicationWindow {
    id: appWindow
    width: appStartWidth
    height: appStartHeight
    minimumWidth: 360
    minimumHeight: 400
    visible: true
    //visibility: isMobile ? ApplicationWindow.FullScreen : ApplicationWindow.Windowed

    readonly property int appStartWidth:    400
    readonly property int appStartHeight:   800
    readonly property int appFitWidth:      Math.max(appCommandsPage.preferredWidth, appStartWidth)
    readonly property int appFitHeight:     Math.max(Math.round(appCommandsPage.preferredWidth * 2.1), appStartHeight)
    readonly property real scrPixelDensity: (isMobile && (Screen.width / Screen.pixelDensity) > 300) ?
                                                Screen.pixelDensity * 2 : Screen.pixelDensity
    readonly property bool appScreenTiny:   (Screen.width / scrPixelDensity) < 120
    readonly property bool appScreenShort:  (Screen.height / scrPixelDensity) < 120 ||
                                                (isMobile && (Screen.height / Screen.width) < 0.6)
    readonly property bool appScreenHuge:   (Screen.width / scrPixelDensity) >= (23.5 * 25.4) // 27" monitor
    readonly property int  appExplainSize:  font.pointSize + 5
    readonly property int  appTitleSize:    font.pointSize + 2 //(font.pointSize >= 12 ? 2 : 1)
    readonly property int  appTipSize:      font.pointSize - 1 //(font.pointSize >= 12 ? 2 : 1)
    readonly property int  appIconSize:     (appToolButton.height * 1.2) & ~1 // make an even number
    readonly property int  appButtonSize:   (appToolButton.height * 1.6) & ~1 // make an even number
    readonly property int  appRowHeight:    Math.ceil(font.pixelSize * 2.5) & ~1 // make an even number
    readonly property int  appTextPadding:  Math.max(Math.ceil(font.pixelSize * 0.25), 2)
    readonly property int  appTipDelay:     750 // milliseconds
    readonly property int  appTipTimeout:   1500 // milliseconds
    readonly property size appDesktopSize:  Qt.size(Screen.desktopAvailableWidth,
                                                    Screen.desktopAvailableHeight - header.height)
    property bool appShowDebug: true
    property bool appForceQuit: false
    property string lastSudoPswd

    property real appOrigFontSize: 0.0
    property int appMaterialTheme: MaterialSet.defaultTheme
    Material.theme:      appMaterialTheme
    Material.accent:     MaterialSet.themeColor[Material.theme]["accent"]
    Material.background: MaterialSet.themeColor[Material.theme]["background"]
    Material.foreground: MaterialSet.themeColor[Material.theme]["foreground"]
    Material.primary:    active ? MaterialSet.themeColor[Material.theme]["primary"]
                                : MaterialSet.themeColor[Material.theme]["shadePrimary"]

    //onActiveFocusControlChanged: console.debug("activeFocusControl", activeFocusControl)
    //onActiveFocusItemChanged: console.debug("activeFocusItem", activeFocusItem)

    MySettings {
        id: appSettings
        property alias width: appWindow.width
        property alias height: appWindow.height
        property alias materialTheme: appWindow.appMaterialTheme
        property alias origFontSize: appWindow.appOrigFontSize
    }
    onFontChanged: appSettings.setValue("lastFontSize", appWindow.font.pointSize)

    Component.onCompleted: {
        if (appWindow.width === appStartWidth && appWindow.height === appStartHeight) {
            appWindow.width = appFitWidth
            appWindow.height = appFitHeight
        }
        if (appOrigFontSize) {
            var ps = appSettings.value("lastFontSize")
            if (ps && ps !== appWindow.font.pointSize) appWindow.font.pointSize = ps
        } else appOrigFontSize = appWindow.font.pointSize

        var env = SystemHelper.envVariable("MYBEE_QT_DEBUG")
        appShowDebug = env ? (env === "1" || env.toLowerCase() === "true")
                           : SystemHelper.loadSettings("showDebug", true)

        SystemProcess.canceled.connect(function() { VMConfigSet.currentProgress = -1 })
        SystemProcess.execError.connect(appError)
        SystemProcess.stdOutputChanged.connect(function(text) {
            if (appShowDebug && VMConfigSet.currentProgress < 0)
                appCommandsPage.appendText(text)
        })
        SystemProcess.stdErrorChanged.connect(function(text) {
            if (text === VMConfigSet.sudoPswd) {
                var dlg = appDialog("SudoPasswordDialog.qml", { password: lastSudoPswd })
                dlg.rejected.connect(SystemProcess.cancel)
                dlg.apply.connect(function() {
                    lastSudoPswd = dlg.password
                    if (!lastSudoPswd) SystemProcess.cancel()
                    else SystemProcess.stdInput(lastSudoPswd)
                })
            } else if (appShowDebug && VMConfigSet.currentProgress < 0)
                appCommandsPage.appendText(text)
        })

        HttpRequest.canceled.connect(function() { VMConfigSet.currentProgress = -1 })
        HttpRequest.recvError.connect(appWarning)
        RestApiSet.message.connect(appLogger)
        VMConfigSet.message.connect(appLogger)
        VMConfigSet.progress.connect(function(text) { appDialog("VMProgressDialog.qml", { title: text }) })
        if (VMConfigSet.cbsdPath) {
            var users = SystemHelper.groupMembers(VMConfigSet.cbsdName)
            if (!users.includes(SystemHelper.userName)) {
                appError(qsTr("User <b>%1</b> must be a member of the <b>%2</b> group to use <i>%3</i>")
                         .arg(SystemHelper.userName).arg(VMConfigSet.cbsdName).arg(VMConfigSet.cbsdPath))
                .accepted.connect(function() {
                    VMConfigSet.cbsdPath = ""
                    VMConfigSet.start()
                })
                return
            }
        }
        VMConfigSet.start()
    }

    onClosing: function(close) {
        if (isMobile && appStackView.depth > 1) {
            appStackView.pop(null)
            close.accepted = false
        } else if (VMConfigSet.isBusy && !appForceQuit) {
            appWarning(qsTr("The system is busy, quit anyway?"), Dialog.Yes | Dialog.No).accepted.connect(function() {
                appForceQuit = true
                Qt.callLater(Qt.quit)
            })
            close.accepted = false
        }
    }

    function appLogger(text) {
        if (appShowDebug && text)
            appCommandsPage.appendText(Qt.formatTime(new Date(), Qt.ISODate) + ' ' + text)
    }

    property var appLastDialog
    function destroyLastDialog() {
        if (appLastDialog) {
            appLastDialog.destroy()
            appLastDialog = undefined
        }
    }

    function appDialog(qml, prop = {}) {
        destroyLastDialog()
        appLastDialog = Qt.createComponent(qml).createObject(appWindow, prop)
        if (appLastDialog) {
            appLastDialog.closed.connect(destroyLastDialog)
            appLastDialog.open()
        } else appToast(qsTr("Can't load %1").arg(qml))
        return appLastDialog
    }

    function appError(text, buttons = Dialog.Abort | Dialog.Ignore) {
        if (!text) text = qsTr("Unexpected shit happened with the RestAPI :(")
        var dlg = appDialog("BriefDialog.qml",
                            { "type": BriefDialog.Type.Error, "text": text, "standardButtons": buttons })
        if (dlg && (buttons & Dialog.Abort)) dlg.rejected.connect(Qt.quit)
        return dlg
    }

    function appWarning(text, buttons = Dialog.Ignore) {
        return appDialog("BriefDialog.qml",
                         { "type": BriefDialog.Type.Warning, "text": text, "standardButtons": buttons })
    }

    function appInfo(text, buttons = Dialog.Ok) {
        return appDialog("BriefDialog.qml",
                         { "type": BriefDialog.Type.Info, "text": text, "standardButtons": buttons })
    }

    function appToast(text) {
        toastComponent.createObject(appWindow, { text })
    }

    function appDelay(interval, func, ...args) { // return Timer instance
        return delayComponent.createObject(appWindow, { interval, func, args });
    }

    function clearDelay(timer) {
        if (timer instanceof Timer) {
            timer.stop()
            timer.destroy()
        } else appToast(qsTr("clearDelay() arg not Timer"))
    }

    function appPage(qml, prop = {}) { // prevent dups
        if (appStackView.find(function(item) { return (item.objectName === qml) })) return null
        var page = appStackView.push(qml, prop)
        if (!page) appToast(qsTr("Can't load %1").arg(qml))
        else if (page instanceof Page) page.objectName = qml
        else appToast(qsTr("Not a Page instance %1").arg(qml))
        return page
    }

    Action {
        shortcut: StandardKey.FullScreen
        onTriggered: {
            visibility = visibility === ApplicationWindow.Windowed ? ApplicationWindow.FullScreen
                                                                   : ApplicationWindow.Windowed
        }
    }
    Action {
        id: appEscapeAction
        shortcut: StandardKey.Cancel
        onTriggered: {
            if (SystemProcess.running) {
                appWarning(qsTr("The process is running, cancel?"), Dialog.Yes | Dialog.No).accepted.connect(SystemProcess.cancel)
            } else if (HttpRequest.running) {
                appWarning(qsTr("The request in progress, cancel?"), Dialog.Yes | Dialog.No).accepted.connect(HttpRequest.cancel)
            } else if (appStackView.depth > 1) {
                appStackView.pop()
            } else {
                appSelectDrawer.visible = !appSelectDrawer.visible
            }
        }
    }

    header: ToolBar {
        id: appToolBar
        StackLayout {
            id: appStackLayout
            anchors.fill: parent
            currentIndex: VMConfigSet.isBusy ? 1 : 0
            RowLayout {
                spacing: 0
                ToolButton {
                    id: appToolButton
                    focusPolicy: Qt.NoFocus
                    icon.source: appStackView.depth > 1 ? "qrc:/icon-back" : "qrc:/icon-menu"
                    action: appEscapeAction
                    rotation: -appSelectDrawer.position * 90
                }
                Image {
                    Layout.maximumHeight: appToolBar.availableHeight
                    Layout.maximumWidth: appToolBar.availableHeight
                    visible: appStackView.depth === 1
                    source: !VMConfigSet.isCreated ? "qrc:/icon-template" :
                        (VMConfigSet.isPowerOn ? "qrc:/icon-power-on" : "qrc:/icon-power-off")
                }
                Label {
                    Layout.fillWidth: true
                    font.pointSize: appTitleSize
                    style: Text.Raised
                    elide: Text.ElideRight
                    text: appStackView.currentItem ? appStackView.currentItem.title : ""
                }
            }
            RowLayout {
                spacing: 0
                ToolButton {
                    focusPolicy: Qt.NoFocus
                    action: appEscapeAction
                    BusyIndicator {
                        anchors.fill: parent
                        running: appStackLayout.currentIndex
                    }
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: SystemProcess.running ? SystemProcess.command : HttpRequest.url.toString()
                }
            }
        }
        /*ProgressBar {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            from: -1; to: 100
            value: VMConfigSet.currentProgress
            visible: value >= 0
            indeterminate: !value
        }*/
    }

    StackView {
        id: appStackView
        anchors.fill: parent
        focus: true // turn-on active focus here
        transform: Translate { x: appSelectDrawer.position * appSelectDrawer.width }
        initialItem: VMCommandsPage { id: appCommandsPage }
        onDepthChanged: VMConfigSet.clusterEnabled = (depth === 1)
    }

    VMSelectDrawer {
        id: appSelectDrawer
        x: 0; y: appWindow.header.height
        width: Math.min(Math.round(appWindow.width * 0.5), 220)
        height: appWindow.contentItem.height
        interactive: appStackView.depth < 2
    }

    Component {
        id: toastComponent
        ToolTip {
            font.pointSize: appTipSize
            timeout: 2500
            visible: text
            onVisibleChanged: if (!visible) destroy()
        }
    }
    Component {
        id: delayComponent
        Timer {
            property var func
            property var args
            running: true
            repeat: false
            onTriggered: {
                func(...args)
                destroy()
            }
        }
    }
}
