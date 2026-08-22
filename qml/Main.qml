import QtQuick 2.15
import QtQuick.Controls 2.15
import net.asivery.AppLoad 1.0

Item {
    id: root
    anchors.fill: parent

    signal close

    property bool closing: false

    function closeApp() {
        if (closing)
            return

        closing = true
        pollTimer.stop()
        pairingWatchdog.stop()
        waitWatchdog.stop()

        Qt.callLater(function() {
            root.close()
        })
    }

    function unloading() {
    }

    property bool hasToken: false
    property bool confirmNotebookTodos: true
    property bool showInSidebar: true
    property string notebookDefaultSpaceId: ""
    property string notebookDefaultSpaceName: ""
    property string notebookDefaultListId: ""
    property string notebookDefaultListName: ""

    property bool configLoaded: false
    property bool busy: false
    property bool linking: false
    property string lastError: ""

    function refreshTodos() {
        root.busy = true
        endpoint.sendMessage(1003, "")
    }

    onBusyChanged: {
        if (root.busy) {
            waitWatchdog.ticks = 0
            waitWatchdog.restart()
        } else {
            waitWatchdog.stop()
        }
    }

    Timer {
        id: waitWatchdog
        interval: 6000
        repeat: true

        property int ticks: 0

        onTriggered: {
            waitWatchdog.ticks += 1
            if (waitWatchdog.ticks === 1) {
                root.lastError = "Still waiting for Saver. Slow connection?"
            } else if (waitWatchdog.ticks >= 4) {
                root.lastError = "Saver isn't responding. Check your Wi-Fi, then tap Refresh."
                root.busy = false
            }
        }
    }

    function startPairing() {
        root.linking = true
        pairingPage.errorText = ""
        pairingPage.statusText = "Contacting Saver..."
        endpoint.sendMessage(1006, "")
        pairingWatchdog.restart()
    }

    Timer {
        id: pairingWatchdog
        interval: 25000
        repeat: false
        onTriggered: {
            if (!root.hasToken && pairingPage.userCode.length === 0) {
                pairingPage.statusText = ""
                pairingPage.errorText = "Could not reach Saver. Check your Wi-Fi, then start over."
            }
        }
    }

    AppLoad {
        id: endpoint
        applicationID: "com.saverapp.remarkable"

        onMessageReceived: (type, contents) => {
            if (root.closing) {
                return
            }
            if (type === 1101) {
                var cfg = JSON.parse(contents)
                root.configLoaded = true
                root.hasToken = cfg.hasToken
                root.confirmNotebookTodos = cfg.confirmNotebookTodos !== false
                root.notebookDefaultSpaceId = cfg.notebookDefaultSpaceId || ""
                root.notebookDefaultSpaceName = cfg.notebookDefaultSpaceName || ""
                root.notebookDefaultListId = cfg.notebookDefaultListId || ""
                root.notebookDefaultListName = cfg.notebookDefaultListName || ""
                root.showInSidebar = cfg.showInSidebar !== false
                if (cfg.hasToken) {
                    root.refreshTodos()
                } else {
                    root.startPairing()
                }
            } else if (type === 1103) {
                root.busy = false
                var listRes = JSON.parse(contents)
                if (listRes.error) {
                    root.lastError = listRes.error
                } else {
                    root.lastError = ""
                    itemsPage.setSpaces(listRes.spaces || [],
                                        listRes.activeSpaceId || "")
                }
            } else if (type === 1105 || type === 1109) {
                var opRes = JSON.parse(contents)
                if (opRes.error) {
                    root.lastError = opRes.error
                    root.refreshTodos()
                }
            } else if (type === 1104 || type === 1110 || type === 1111
                       || type === 1112 || type === 1113 || type === 1114) {
                var createRes = JSON.parse(contents)
                if (createRes.error) {
                    root.busy = false
                    root.lastError = createRes.error
                } else {
                    root.refreshTodos()
                }
            } else if (type === 1106) {
                var startRes = JSON.parse(contents)
                if (startRes.error) {
                    pairingPage.statusText = ""
                    pairingPage.errorText = startRes.error
                    pollTimer.stop()
                    pairingWatchdog.stop()
                } else {
                    pairingWatchdog.stop()
                    pairingPage.userCode = startRes.userCode
                    pairingPage.verificationUrl = startRes.verificationUrl
                    pairingPage.qrSize = startRes.qr.size
                    pairingPage.qrModules = startRes.qr.modules
                    pairingPage.errorText = ""
                    pairingPage.statusText = "Waiting for you to approve…"
                    pollTimer.interval = Math.max(1, startRes.interval) * 1000
                    pollTimer.start()
                }
            } else if (type === 1107) {
                var pollRes = JSON.parse(contents)
                if (pollRes.error) {
                    pairingPage.statusText = pollRes.error
                } else if (pollRes.status === "approved") {
                    pollTimer.stop()
                    root.linking = false
                    root.hasToken = true
                    root.refreshTodos()
                } else if (pollRes.status === "expired") {
                    pollTimer.stop()
                    pairingPage.statusText = ""
                    pairingPage.errorText = "That code expired before it was approved."
                } else {
                    pairingPage.statusText = "Waiting for you to approve…"
                }
            } else if (type === 1115) {
                var activeRes = JSON.parse(contents)
                if (activeRes.error) {
                    root.lastError = activeRes.error
                }
            } else if (type === 1102) {
                var saveRes = JSON.parse(contents)
                if (saveRes.error) {
                    root.lastError = saveRes.error
                } else if (saveRes.ok) {
                    root.confirmNotebookTodos = saveRes.confirmNotebookTodos !== false
                    root.notebookDefaultSpaceId = saveRes.notebookDefaultSpaceId || ""
                    root.notebookDefaultSpaceName = saveRes.notebookDefaultSpaceName || ""
                    root.notebookDefaultListId = saveRes.notebookDefaultListId || ""
                    root.notebookDefaultListName = saveRes.notebookDefaultListName || ""
                    root.showInSidebar = saveRes.showInSidebar !== false
                }
            } else if (type === 1108) {
                root.hasToken = false
                root.startPairing()
            }
        }
    }

    Timer {
        interval: 300
        running: true
        repeat: false
        onTriggered: endpoint.sendMessage(1001, "")
    }

    Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        onTriggered: endpoint.sendMessage(1007, "")
    }

    Item {
        anchors.fill: parent
        visible: !root.configLoaded

        Label {
            anchors.centerIn: parent
            text: "Starting..."
            font.pixelSize: 30
            color: "black"
            opacity: 0.5
            visible: slowStartTimer.elapsed
        }

        Timer {
            id: slowStartTimer
            property bool elapsed: false
            interval: 1500
            running: !root.configLoaded
            repeat: false
            onTriggered: slowStartTimer.elapsed = true
        }
    }

    PairingPage {
        id: pairingPage
        anchors.fill: parent
        visible: root.configLoaded && !root.hasToken && !root.closing
        onRetry: root.startPairing()
        onCloseApp: root.closeApp()
    }

    ItemsPage {
        id: itemsPage
        anchors.fill: parent
        visible: root.configLoaded && root.hasToken && !root.closing
        errorText: root.lastError
        busy: root.busy
        confirmNotebookTodos: root.confirmNotebookTodos
        notebookDefaultSpaceId: root.notebookDefaultSpaceId
        notebookDefaultSpaceName: root.notebookDefaultSpaceName
        notebookDefaultListId: root.notebookDefaultListId
        notebookDefaultListName: root.notebookDefaultListName
        showInSidebar: root.showInSidebar
        onToggleTodo: (spaceId, todoId, isDone) => {
            endpoint.sendMessage(1005, JSON.stringify({
                spaceId: spaceId,
                todoId: todoId,
                isDone: isDone,
            }))
        }
        onSetHabitCount: (spaceId, habitId, count) => {
            endpoint.sendMessage(1009, JSON.stringify({
                spaceId: spaceId,
                habitId: habitId,
                count: count,
            }))
        }
        onRefresh: root.refreshTodos()
        onUnlink: endpoint.sendMessage(1008, "")
        onSetConfirmNotebookTodos: (enabled) => {
            root.confirmNotebookTodos = enabled
            endpoint.sendMessage(1002, JSON.stringify({
                confirmNotebookTodos: enabled,
            }))
        }
        onSetNotebookDefaultSpace: (spaceId, spaceName) => {
            root.notebookDefaultSpaceId = spaceId
            root.notebookDefaultSpaceName = spaceName
            root.notebookDefaultListId = ""
            root.notebookDefaultListName = ""
            endpoint.sendMessage(1002, JSON.stringify({
                notebookDefaultSpaceId: spaceId,
                notebookDefaultSpaceName: spaceName,
            }))
        }
        onClearNotebookDefaultSpace: {
            root.notebookDefaultSpaceId = ""
            root.notebookDefaultSpaceName = ""
            root.notebookDefaultListId = ""
            root.notebookDefaultListName = ""
            endpoint.sendMessage(1002, JSON.stringify({
                clearNotebookDefaultSpace: true,
            }))
        }
        onSetNotebookDefaultList: (listId, listName) => {
            root.notebookDefaultListId = listId
            root.notebookDefaultListName = listName
            endpoint.sendMessage(1002, JSON.stringify({
                notebookDefaultListId: listId,
                notebookDefaultListName: listName,
            }))
        }
        onClearNotebookDefaultList: {
            root.notebookDefaultListId = ""
            root.notebookDefaultListName = ""
            endpoint.sendMessage(1002, JSON.stringify({
                clearNotebookDefaultList: true,
            }))
        }
        onSetShowInSidebar: (enabled) => {
            root.showInSidebar = enabled
            endpoint.sendMessage(1002, JSON.stringify({
                showInSidebar: enabled,
            }))
        }
        onSetActiveSpace: (spaceId) => {
            endpoint.sendMessage(1015, JSON.stringify({
                spaceId: spaceId,
            }))
        }
        onCloseApp: root.closeApp()
        onCreateTodo: (spaceId, text, parentId, isList) => {
            root.busy = true
            endpoint.sendMessage(1004, JSON.stringify({
                spaceId: spaceId,
                text: text,
                parentId: parentId,
                isList: isList,
            }))
        }
        onCreateBookmark: (spaceId, title, url, isList, parentId) => {
            root.busy = true
            endpoint.sendMessage(1010, JSON.stringify({
                spaceId: spaceId,
                title: title,
                url: url,
                isList: isList,
                parentId: parentId,
            }))
        }
        onCreateHabit: (spaceId, name, requirement) => {
            root.busy = true
            endpoint.sendMessage(1011, JSON.stringify(Object.assign({
                spaceId: spaceId,
                name: name,
            }, requirement)))
        }
        onUpdateTodo: (spaceId, todoId, text) => {
            root.busy = true
            endpoint.sendMessage(1013, JSON.stringify({
                spaceId: spaceId,
                todoId: todoId,
                text: text,
            }))
        }
        onUpdateBookmark: (spaceId, bookmarkId, title, url, isList) => {
            root.busy = true
            endpoint.sendMessage(1014, JSON.stringify({
                spaceId: spaceId,
                bookmarkId: bookmarkId,
                title: title,
                url: url,
                isList: isList,
            }))
        }
        onUpdateHabit: (spaceId, habitId, name, requirement) => {
            root.busy = true
            endpoint.sendMessage(1012, JSON.stringify(Object.assign({
                spaceId: spaceId,
                habitId: habitId,
                name: name,
            }, requirement)))
        }
    }
}
