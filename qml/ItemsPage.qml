import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import net.asivery.ApploadUtils 1.0

Page {
    id: page

    property string errorText: ""
    property bool busy: false

    property bool confirmNotebookTodos: true
    property bool showInSidebar: true

    property string notebookDefaultSpaceId: ""
    property string notebookDefaultSpaceName: ""
    property string notebookDefaultListId: ""
    property string notebookDefaultListName: ""

    function topLevelLists(spaceId) {
        var result = []
        for (var i = 0; i < page.spaces.length; i++) {
            if (page.spaces[i].id !== spaceId) continue
            var todos = page.spaces[i].todos || []
            for (var t = 0; t < todos.length; t++) {
                if (todos[t].isList === true && !todos[t].parentId) {
                    result.push({ id: todos[t].id, title: todos[t].text || "" })
                }
            }
            break
        }
        return result
    }

    property var spaces: []

    // Drop a stored default the account no longer has, rather than sending it
    // with handwritten todos.
    onSpacesChanged: {
        if (page.spaces.length === 0)
            return
        if (page.notebookDefaultSpaceId.length > 0) {
            var known = false
            for (var s = 0; s < page.spaces.length; s++) {
                if (page.spaces[s].id === page.notebookDefaultSpaceId) {
                    known = true
                    break
                }
            }
            if (!known) {
                page.clearNotebookDefaultSpace()
                return
            }
        }
        if (page.notebookDefaultListId.length === 0)
            return
        var lists = page.topLevelLists(page.notebookDefaultSpaceId)
        for (var i = 0; i < lists.length; i++) {
            if (lists[i].id === page.notebookDefaultListId)
                return
        }
        page.clearNotebookDefaultList()
    }

    property int spaceIndex: 0

    property var todoPath: []
    property var bookmarkPath: []

    signal toggleTodo(string spaceId, string todoId, bool isDone)
    signal setHabitCount(string spaceId, string habitId, int count)
    signal refresh()
    signal unlink()
    signal closeApp()
    signal setActiveSpace(string spaceId)
    signal createTodo(string spaceId, string text, var parentId, bool isList)
    signal createBookmark(string spaceId, string title, string url,
                          bool isList, var parentId)
    signal createHabit(string spaceId, string name, var requirement)
    signal updateHabit(string spaceId, string habitId, string name,
                       var requirement)
    signal setConfirmNotebookTodos(bool enabled)
    signal setShowInSidebar(bool enabled)
    signal setNotebookDefaultSpace(string spaceId, string spaceName)
    signal clearNotebookDefaultSpace()
    signal setNotebookDefaultList(string listId, string listName)
    signal clearNotebookDefaultList()
    signal updateTodo(string spaceId, string todoId, string text)
    signal updateBookmark(string spaceId, string bookmarkId, string title,
                          string url, bool isList)

    background: Rectangle { color: "white" }

    readonly property int rowHeight: 120
    readonly property int titleSize: 34
    readonly property int metaSize: 24

    function setSpaces(list, activeId) {
        var previousId = currentSpaceId()
        spaces = list || []

        var wanted = previousId.length > 0 ? previousId : (activeId || "")
        var index = 0
        for (var i = 0; i < spaces.length; i++) {
            if (spaces[i].id === wanted) { index = i; break }
        }
        spaceIndex = index

        var names = []
        for (var n = 0; n < spaces.length; n++) {
            names.push(spaces[n].name)
        }
        spaceSelector.model = names
        spaceSelector.currentIndex = index

        rebuild()
    }

    function currentSpace() {
        return (spaceIndex >= 0 && spaceIndex < spaces.length)
            ? spaces[spaceIndex] : null
    }

    function currentSpaceId() {
        var space = currentSpace()
        return space ? space.id : ""
    }

    function selectSpace(index) {
        if (index === spaceIndex) return
        spaceIndex = index
        todoPath = []
        bookmarkPath = []
        rebuild()
        page.setActiveSpace(currentSpaceId())
    }

    function currentParentId(path) {
        return path.length > 0 ? path[path.length - 1].id : null
    }

    function sortItems(items, titleKey) {
        return items.sort(function (a, b) {
            if (a.isList !== b.isList) return a.isList ? -1 : 1
            var left = (a[titleKey] || "").toLowerCase()
            var right = (b[titleKey] || "").toLowerCase()
            return left < right ? -1 : (left > right ? 1 : 0)
        })
    }

    function rebuild() {
        todosModel.clear()
        bookmarksModel.clear()
        habitsModel.clear()

        var space = currentSpace()
        if (!space) return

        var todoParent = currentParentId(todoPath)
        var todos = (space.todos || []).filter(function (todo) {
            return (todo.parentId || null) === todoParent
        })
        sortItems(todos, "text")
        for (var t = 0; t < todos.length; t++) {
            var todo = todos[t]
            todosModel.append({
                itemId: todo.id,
                title: todo.text || "",
                isDone: todo.isDone === true,
                isList: todo.isList === true,
                hasSubTodos: todo.hasSubTodos === true,
            })
        }

        var bookmarkParent = currentParentId(bookmarkPath)
        var bookmarks = (space.bookmarks || []).filter(function (bookmark) {
            return (bookmark.parentId || null) === bookmarkParent
        })
        sortItems(bookmarks, "title")
        for (var b = 0; b < bookmarks.length; b++) {
            var bookmark = bookmarks[b]
            bookmarksModel.append({
                itemId: bookmark.id,
                title: bookmark.title || "",
                url: bookmark.url || "",
                isList: bookmark.isList === true,
            })
        }

        var habits = space.habits || []
        for (var h = 0; h < habits.length; h++) {
            var habit = habits[h]
            habitsModel.append({
                itemId: habit.id,
                title: habit.name || "",
                count: habit.count,
                required: habit.requiredCountPerDay,
                isDoneToday: habit.isDoneToday === true,
                streak: habit.streak,
                requirementMode: habit.requirementMode || "everyday",
                windowSizeDays: habit.windowSizeDays || 7,
                requiredDays: habit.requiredDays || 7,
                approvaleCount: habit.approvaleCount || 1,
                anchorDate: habit.anchorDate || "",
            })
        }
    }

    function scheduleLabel(mode, requiredDays, windowSizeDays) {
        if (mode === "everyday" || requiredDays >= windowSizeDays) {
            return "every day"
        }
        if (windowSizeDays === 7) return requiredDays + " days a week"
        if (windowSizeDays === 14) return requiredDays + " days per 14 days"
        return requiredDays + " days per " + windowSizeDays
    }

    function applyTodoDoneLocally(itemId, isDone) {
        var space = currentSpace()
        if (!space) return
        var todos = space.todos || []
        for (var i = 0; i < todos.length; i++) {
            if (todos[i].id === itemId) { todos[i].isDone = isDone; return }
        }
    }

    function applyHabitCountLocally(itemId, count, isDoneToday) {
        var space = currentSpace()
        if (!space) return
        var habits = space.habits || []
        for (var i = 0; i < habits.length; i++) {
            if (habits[i].id === itemId) {
                habits[i].count = count
                habits[i].isDoneToday = isDoneToday
                return
            }
        }
    }

    function commitHabitCount(rowIndex, itemId, count, required) {
        var done = count >= required
        habitsModel.setProperty(rowIndex, "count", count)
        habitsModel.setProperty(rowIndex, "isDoneToday", done)
        applyHabitCountLocally(itemId, count, done)
        setHabitCount(currentSpaceId(), itemId, count)
    }

    function enterFolder(which, id, title) {
        if (which === "todos") {
            todoPath = todoPath.concat([{ id: id, title: title }])
        } else {
            bookmarkPath = bookmarkPath.concat([{ id: id, title: title }])
        }
        rebuild()
    }

    function goToDepth(which, depth) {
        if (which === "todos") {
            todoPath = todoPath.slice(0, depth)
        } else {
            bookmarkPath = bookmarkPath.slice(0, depth)
        }
        rebuild()
    }

    ListModel { id: todosModel }
    ListModel { id: bookmarksModel }
    ListModel { id: habitsModel }

    component Breadcrumb: Rectangle {
        id: crumbRoot

        property string which: "todos"
        property var path: []

        implicitHeight: crumbRoot.path.length > 0 ? 76 : 0
        visible: crumbRoot.path.length > 0
        color: "#f0f0f0"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 12

            Button {
                text: "Back"
                onClicked: page.goToDepth(crumbRoot.which, crumbRoot.path.length - 1)
                contentItem: Text {
                    text: "Back"
                    font.pixelSize: 26
                    font.bold: true
                    color: "black"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "white"
                    border.color: "black"
                    border.width: 2
                    radius: 6
                }
                padding: 14
            }

            Label {
                text: {
                    var names = []
                    for (var i = 0; i < crumbRoot.path.length; i++) {
                        names.push(crumbRoot.path[i].title)
                    }
                    return names.join("  /  ")
                }
                font.pixelSize: 26
                color: "black"
                elide: Text.ElideLeft
                Layout.fillWidth: true
            }
        }
    }

    component PanelField: TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: 96
        font.pixelSize: 34
        color: "black"
        background: Rectangle {
            color: "white"
            border.color: "black"
            border.width: 2
            radius: 6
        }
        onAccepted: newItemPanel.submit()
    }

    component PanelLabel: Label {
        font.pixelSize: 26
        color: "black"
        opacity: 0.6
    }

    component StepButton: Button {
        property string symbol: "+"
        Layout.preferredWidth: 96
        Layout.preferredHeight: 88
        contentItem: Text {
            text: symbol
            font.pixelSize: 40
            font.bold: true
            color: "black"
            opacity: parent.enabled ? 1.0 : 0.3
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: "white"
            border.color: "black"
            border.width: 2
            radius: 8
        }
    }

    component Stepper: RowLayout {
        id: stepper

        property string label: ""
        property int value: 1
        property int minimum: 1
        property int maximum: 999
        property bool editable: true
        signal stepped(int next)

        spacing: 20

        Label {
            text: stepper.label
            font.pixelSize: 30
            color: "black"
            opacity: stepper.editable ? 1.0 : 0.35
            elide: Text.ElideRight
            Layout.preferredWidth: 470
        }

        StepButton {
            symbol: "-"
            enabled: stepper.editable && stepper.value > stepper.minimum
            onClicked: stepper.stepped(stepper.value - 1)
        }

        Label {
            text: stepper.value
            font.pixelSize: 40
            font.bold: true
            color: "black"
            opacity: stepper.editable ? 1.0 : 0.35
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: 100
        }

        StepButton {
            symbol: "+"
            enabled: stepper.editable && stepper.value < stepper.maximum
            onClicked: stepper.stepped(stepper.value + 1)
        }

        Item { Layout.fillWidth: true }
    }

    component ModeButton: Button {
        property string mode: ""
        property string labelText: ""
        readonly property bool selected: newItemPanel.habitMode === mode

        Layout.fillWidth: true
        Layout.preferredHeight: 96
        onClicked: newItemPanel.applyRequirementMode(mode)

        contentItem: Text {
            text: labelText
            font.pixelSize: 24
            font.bold: selected
            color: "black"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
        background: Rectangle {
            color: "white"
            border.color: "black"
            border.width: selected ? 5 : 2
            radius: 8
        }
    }

    component EditButton: Button {
        Layout.preferredWidth: 116
        Layout.preferredHeight: 76
        contentItem: Text {
            text: "Edit"
            font.pixelSize: 26
            color: "black"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: "white"
            border.color: "black"
            border.width: 2
            radius: 8
        }
    }

    component RowSeparator: Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: "#d0d0d0"
    }

    component SaverListView: ListView {
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        pressDelay: 120

        pixelAligned: true

        ScrollBar.vertical: ScrollBar { width: 16 }
    }

    component SaverScrollView: Item {
        id: scrollRoot

        property alias model: list.model
        property alias delegate: list.delegate
        property alias contentHeight: list.contentHeight

        implicitHeight: list.contentHeight

        SaverListView {
            id: list
            anchors.fill: parent
        }

        DisplayMethodArea {
            anchors.fill: parent
            displayMethod: list.moving
                ? DisplayMethodArea.Animate
                : DisplayMethodArea.UI
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            color: "white"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 16

                ComboBox {
                    id: spaceSelector
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84
                    model: []
                    onActivated: page.selectSpace(index)

                    contentItem: Text {
                        leftPadding: 20
                        rightPadding: 20
                        text: spaceSelector.displayText
                        font.pixelSize: 34
                        font.bold: true
                        color: "black"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 8
                    }
                    indicator: Text {
                        x: spaceSelector.width - width - 20
                        y: (spaceSelector.height - height) / 2
                        text: "v"
                        font.pixelSize: 32
                        color: "black"
                    }

                    delegate: ItemDelegate {
                        width: spaceSelector.width
                        height: 88
                        contentItem: Text {
                            text: modelData
                            font.pixelSize: 32
                            font.bold: spaceSelector.currentIndex === index
                            color: "black"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            color: "white"
                            border.color: "#d0d0d0"
                            border.width: 1
                        }
                    }
                    popup: Popup {
                        y: spaceSelector.height
                        width: spaceSelector.width
                        implicitHeight: Math.min(contentItem.implicitHeight, 600)
                        padding: 2
                        contentItem: SaverScrollView {
                            implicitHeight: contentHeight
                            model: spaceSelector.popup.visible ? spaceSelector.delegateModel : null
                        }
                        background: Rectangle {
                            color: "white"
                            border.color: "black"
                            border.width: 2
                        }
                    }
                }

                Button {
                    text: page.busy ? "…" : "Refresh"
                    enabled: !page.busy
                    onClicked: page.refresh()
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 6
                    }
                    padding: 16
                }

                Button {
                    text: "Settings"
                    onClicked: settingsPanel.visible = true
                    contentItem: Text {
                        text: "Settings"
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 6
                    }
                    padding: 16
                }

                Button {
                    text: "Unlink"
                    onClicked: page.unlink()
                    contentItem: Text {
                        text: "Unlink"
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 6
                    }
                    padding: 16
                }

                Button {
                    enabled: page.spaces.length > 0
                    onClicked: newItemPanel.openPanel(tabBar.currentIndex)
                    contentItem: Text {
                        text: "+ New"
                        font.pixelSize: 26
                        font.bold: true
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 3
                        radius: 6
                    }
                    padding: 16
                }

                Button {
                    text: "Close"
                    onClicked: page.closeApp()
                    contentItem: Text {
                        text: "Close"
                        font.pixelSize: 26
                        font.bold: true
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 3
                        radius: 6
                    }
                    padding: 16
                }
            }
        }

        Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }

        Label {
            text: page.errorText
            visible: page.errorText.length > 0
            color: "black"
            font.pixelSize: 26
            wrapMode: Text.WordWrap
            padding: 20
            Layout.fillWidth: true
        }

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            Layout.preferredHeight: 118
            spacing: 0
            background: Rectangle { color: "white" }

            component TabLabel: TabButton {
                id: tabLabel

                property int tabIndex: 0
                property string label: ""
                property int count: 0
                readonly property bool active: tabBar.currentIndex === tabLabel.tabIndex

                contentItem: Column {
                    spacing: 4
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tabLabel.count
                        font.pixelSize: 26
                        color: "black"
                        opacity: tabLabel.active ? 0.75 : 0.45
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tabLabel.label
                        font.pixelSize: 36
                        font.bold: tabLabel.active
                        color: "black"
                    }
                }

                background: Rectangle {
                    color: "white"

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 48
                        height: tabLabel.active ? 8 : 2
                        color: tabLabel.active ? "black" : "#c8c8c8"
                    }
                }
            }

            TabLabel { tabIndex: 0; label: "Todos"; count: todosModel.count }
            TabLabel { tabIndex: 1; label: "Bookmarks"; count: bookmarksModel.count }
            TabLabel { tabIndex: 2; label: "Habits"; count: habitsModel.count }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#c8c8c8" }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            ColumnLayout {
                spacing: 0
                Breadcrumb {
                    which: "todos"
                    path: page.todoPath
                    Layout.fillWidth: true
                }
                SaverScrollView {
                    id: todoList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: todosModel

                    delegate: Item {
                        width: todoList.width
                        height: page.rowHeight

                        MouseArea {
                            anchors.fill: parent
                            enabled: model.isList
                            onClicked: page.enterFolder("todos", model.itemId, model.title)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 24
                            spacing: 20

                            Item {
                                visible: !model.isList
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 56

                                Rectangle {
                                    anchors.fill: parent
                                    color: "white"
                                    border.color: "black"
                                    border.width: 3
                                }

                                Canvas {
                                    id: tick
                                    anchors.fill: parent
                                    visible: model.isDone
                                    onVisibleChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        if (!visible) return
                                        ctx.strokeStyle = "black"
                                        ctx.lineWidth = 7
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"
                                        ctx.beginPath()
                                        ctx.moveTo(width * 0.20, height * 0.52)
                                        ctx.lineTo(width * 0.42, height * 0.74)
                                        ctx.lineTo(width * 0.80, height * 0.26)
                                        ctx.stroke()
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -18
                                    onClicked: {
                                        var next = !model.isDone
                                        todosModel.setProperty(index, "isDone", next)
                                        page.applyTodoDoneLocally(model.itemId, next)
                                        page.toggleTodo(page.currentSpaceId(), model.itemId, next)
                                    }
                                }
                            }

                            Canvas {
                                visible: model.isList
                                Layout.preferredWidth: 52
                                Layout.preferredHeight: 52
                                Component.onCompleted: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = "black"
                                    ctx.fillStyle = "black"
                                    ctx.lineWidth = 3
                                    ctx.lineCap = "round"
                                    var rows = [0.28, 0.5, 0.72]
                                    for (var i = 0; i < rows.length; i++) {
                                        var y = height * rows[i]
                                        ctx.beginPath()
                                        ctx.arc(width * 0.16, y, 3.5, 0, 2 * Math.PI)
                                        ctx.fill()
                                        ctx.beginPath()
                                        ctx.moveTo(width * 0.34, y)
                                        ctx.lineTo(width * 0.88, y)
                                        ctx.stroke()
                                    }
                                }
                            }

                            Label {
                                text: model.title
                                font.pixelSize: page.titleSize
                                font.bold: model.isList
                                font.strikeout: !model.isList && model.isDone
                                color: "black"
                                opacity: (!model.isList && model.isDone) ? 0.5 : 1.0
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Button {
                                visible: !model.isList
                                Layout.preferredWidth: 116
                                Layout.preferredHeight: 76
                                onClicked: newItemPanel.openSubTodo(todosModel.get(index))
                                contentItem: Text {
                                    text: "+ Sub"
                                    font.pixelSize: 26
                                    color: "black"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: "white"
                                    border.color: "black"
                                    border.width: 2
                                    radius: 8
                                }
                            }

                            EditButton {
                                onClicked: newItemPanel.openTodo(todosModel.get(index))
                            }

                            Item {
                                visible: model.isList || model.hasSubTodos
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 60

                                Canvas {
                                    anchors.fill: parent
                                    Component.onCompleted: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.strokeStyle = "black"
                                        ctx.lineWidth = 4
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"
                                        ctx.beginPath()
                                        ctx.moveTo(width * 0.35, height * 0.30)
                                        ctx.lineTo(width * 0.68, height * 0.5)
                                        ctx.lineTo(width * 0.35, height * 0.70)
                                        ctx.stroke()
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -16
                                    enabled: model.hasSubTodos && !model.isList
                                    onClicked: page.enterFolder("todos", model.itemId, model.title)
                                }
                            }
                        }

                        RowSeparator {}
                    }
                }
            }

            ColumnLayout {
                spacing: 0
                Breadcrumb {
                    which: "bookmarks"
                    path: page.bookmarkPath
                    Layout.fillWidth: true
                }
                SaverScrollView {
                    id: bookmarkList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: bookmarksModel

                    delegate: Item {
                        width: bookmarkList.width
                        height: page.rowHeight

                        MouseArea {
                            anchors.fill: parent
                            enabled: model.isList
                            onClicked: page.enterFolder("bookmarks", model.itemId, model.title)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 24
                            spacing: 20

                            Canvas {
                                visible: model.isList
                                Layout.preferredWidth: 52
                                Layout.preferredHeight: 52
                                Component.onCompleted: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = "black"
                                    ctx.lineWidth = 3
                                    ctx.beginPath()
                                    ctx.moveTo(width * 0.08, height * 0.80)
                                    ctx.lineTo(width * 0.08, height * 0.26)
                                    ctx.lineTo(width * 0.42, height * 0.26)
                                    ctx.lineTo(width * 0.50, height * 0.38)
                                    ctx.lineTo(width * 0.92, height * 0.38)
                                    ctx.lineTo(width * 0.92, height * 0.80)
                                    ctx.closePath()
                                    ctx.stroke()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    text: model.title.length > 0 ? model.title : model.url
                                    font.pixelSize: page.titleSize
                                    font.bold: model.isList
                                    color: "black"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: model.url
                                    visible: !model.isList && model.url.length > 0
                                    font.pixelSize: page.metaSize
                                    color: "black"
                                    opacity: 0.55
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            EditButton {
                                onClicked: newItemPanel.openBookmark(bookmarksModel.get(index))
                            }

                            Canvas {
                                visible: model.isList
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 44
                                Component.onCompleted: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = "black"
                                    ctx.lineWidth = 4
                                    ctx.lineCap = "round"
                                    ctx.lineJoin = "round"
                                    ctx.beginPath()
                                    ctx.moveTo(width * 0.3, height * 0.28)
                                    ctx.lineTo(width * 0.72, height * 0.5)
                                    ctx.lineTo(width * 0.3, height * 0.72)
                                    ctx.stroke()
                                }
                            }
                        }

                        RowSeparator {}
                    }
                }
            }

            SaverScrollView {
                id: habitList
                model: habitsModel

                delegate: Item {
                    width: habitList.width
                    height: page.rowHeight

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        spacing: 20

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Label {
                                text: model.title
                                font.pixelSize: page.titleSize
                                color: "black"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: (model.required > 1
                                       ? model.count + " / " + model.required + " today"
                                       : (model.isDoneToday ? "Done today" : "Not done today"))
                                      + "  ·  " + page.scheduleLabel(model.requirementMode,
                                                                    model.requiredDays,
                                                                    model.windowSizeDays)
                                      + (model.streak > 0 ? "  ·  streak " + model.streak : "")
                                font.pixelSize: page.metaSize
                                color: "black"
                                opacity: 0.55
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        EditButton {
                            onClicked: newItemPanel.openHabit(habitsModel.get(index))
                        }

                        Button {
                            visible: model.required > 1 && model.count > 0
                            Layout.preferredWidth: 76
                            Layout.preferredHeight: 76
                            onClicked: page.commitHabitCount(
                                index, model.itemId,
                                Math.max(0, model.count - 1), model.required)

                            contentItem: Text {
                                text: "-"
                                font.pixelSize: 34
                                font.bold: true
                                color: "black"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: "white"
                                border.color: "black"
                                border.width: 2
                                radius: 8
                            }
                        }

                        Button {
                            Layout.preferredWidth: 150
                            Layout.preferredHeight: 76
                            onClicked: {
                                var nextCount = model.isDoneToday
                                    ? 0
                                    : Math.min(model.required, model.count + 1)
                                page.commitHabitCount(index, model.itemId,
                                                      nextCount, model.required)
                            }

                            contentItem: Text {
                                text: model.isDoneToday
                                    ? "Done"
                                    : (model.required > 1 ? "+1" : "Mark")
                                font.pixelSize: 28
                                font.bold: true
                                color: "black"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: "white"
                                border.color: "black"
                                border.width: model.isDoneToday ? 5 : 2
                                radius: 8
                            }
                        }
                    }

                    RowSeparator {}
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: todosModel.count === 0 && bookmarksModel.count === 0
                 && habitsModel.count === 0 && page.errorText.length === 0
        text: page.busy ? "Loading..."
              : (page.spaces.length === 0 ? "No spaces yet." : "Nothing here.")
        font.pixelSize: 34
        color: "black"
        opacity: 0.6
    }

    Rectangle {
        id: newItemPanel
        anchors.fill: parent
        color: "white"
        visible: false
        z: 100

        property string kind: "todo"

        property string todoId: ""
        property string bookmarkId: ""

        property bool todoIsList: false

        property bool todoAsList: false

        property string todoParentOverride: ""
        property string todoParentTitle: ""

        property string habitId: ""
        property string habitMode: "everyday"
        property int habitWindowDays: 7
        property int habitRequiredDays: 7
        property int habitRequired: 1
        property int habitApprovals: 1
        property var habitAnchor: new Date()

        readonly property bool habitIsEveryday: habitMode === "everyday"

        readonly property bool isEdit: {
            if (kind === "todo") return todoId.length > 0
            if (kind === "bookmark") return bookmarkId.length > 0
            return habitId.length > 0
        }

        function applyRequirementMode(mode) {
            habitMode = mode
            if (mode === "everyday") {
                habitWindowDays = 7
                habitRequiredDays = 7
            } else if (mode === "week") {
                habitWindowDays = 7
                habitRequiredDays = Math.min(7, Math.max(1, habitRequiredDays))
            } else if (mode === "fortnight") {
                habitWindowDays = 14
                habitRequiredDays = Math.min(14, Math.max(1, habitRequiredDays))
            } else {
                habitRequiredDays = Math.min(habitWindowDays, habitRequiredDays)
            }
        }

        function setWindowDays(days) {
            habitWindowDays = days
            if (habitRequiredDays > days) habitRequiredDays = days
        }

        function shiftAnchor(days) {
            var next = new Date(habitAnchor.getTime())
            next.setDate(next.getDate() + days)
            habitAnchor = next
        }

        function defaultAnchor() {
            var now = new Date()
            var monday = new Date(now.getFullYear(), now.getMonth(),
                                  now.getDate() - ((now.getDay() + 6) % 7))
            return monday
        }

        readonly property string destination: {
            var space = page.currentSpace()
            var spaceName = space ? space.name : ""
            if (kind === "todo") {
                if (todoParentOverride.length > 0) return todoParentTitle
                return page.todoPath.length > 0
                    ? page.todoPath[page.todoPath.length - 1].title : spaceName
            }
            if (kind === "bookmark") {
                return page.bookmarkPath.length > 0
                    ? page.bookmarkPath[page.bookmarkPath.length - 1].title
                    : spaceName
            }
            return spaceName
        }

        readonly property bool canSubmit: {
            if (kind === "todo") return todoField.text.trim().length > 0
            if (kind === "habit") return habitNameField.text.trim().length > 0
            if (bookmarkIsFolder) return bookmarkTitleField.text.trim().length > 0
            return bookmarkTitleField.text.trim().length > 0
                || bookmarkUrlField.text.trim().length > 0
        }
        property bool bookmarkIsFolder: false

        function openPanel(tabIndex) {
            kind = tabIndex === 1 ? "bookmark" : (tabIndex === 2 ? "habit" : "todo")
            todoId = ""
            bookmarkId = ""
            todoIsList = false
            todoAsList = false
            todoParentOverride = ""
            todoParentTitle = ""
            todoField.text = ""
            bookmarkTitleField.text = ""
            bookmarkUrlField.text = ""
            bookmarkIsFolder = false
            habitNameField.text = ""
            habitId = ""
            habitMode = "everyday"
            habitWindowDays = 7
            habitRequiredDays = 7
            habitRequired = 1
            habitApprovals = 1
            habitAnchor = defaultAnchor()
            visible = true
            if (kind === "todo") todoField.forceActiveFocus()
            else if (kind === "bookmark") bookmarkTitleField.forceActiveFocus()
            else habitNameField.forceActiveFocus()
        }

        function openTodo(row) {
            kind = "todo"
            todoId = row.itemId
            todoIsList = row.isList === true
            todoAsList = false
            todoParentOverride = ""
            todoParentTitle = ""
            todoField.text = row.title
            visible = true
            todoField.forceActiveFocus()
        }

        function openSubTodo(row) {
            kind = "todo"
            todoId = ""
            todoIsList = false
            todoAsList = false
            todoParentOverride = row.itemId
            todoParentTitle = row.title
            todoField.text = ""
            visible = true
            todoField.forceActiveFocus()
        }

        function openBookmark(row) {
            kind = "bookmark"
            todoId = ""
            todoIsList = false
            todoParentOverride = ""
            bookmarkId = row.itemId
            bookmarkIsFolder = row.isList === true
            bookmarkTitleField.text = row.title
            bookmarkUrlField.text = row.url || ""
            visible = true
            bookmarkTitleField.forceActiveFocus()
        }

        function openHabit(row) {
            kind = "habit"
            todoId = ""
            todoIsList = false
            todoParentOverride = ""
            bookmarkId = ""
            habitId = row.itemId
            habitNameField.text = row.title
            habitMode = row.requirementMode
            habitWindowDays = row.windowSizeDays
            habitRequiredDays = row.requiredDays
            habitRequired = row.required
            habitApprovals = row.approvaleCount
            var parsed = row.anchorDate.length > 0 ? new Date(row.anchorDate) : null
            habitAnchor = (parsed && !isNaN(parsed.getTime()))
                ? parsed : defaultAnchor()
            visible = true
            habitNameField.forceActiveFocus()
        }

        function habitRequirement() {
            return {
                requirementMode: habitMode,
                windowSizeDays: habitWindowDays,
                requiredDays: habitRequiredDays,
                requiredCountPerDay: habitRequired,
                approvaleCount: habitApprovals,
                anchorDate: habitAnchor.toISOString(),
            }
        }

        function submit() {
            if (!canSubmit) return
            var spaceId = page.currentSpaceId()
            if (kind === "todo" && todoId.length > 0) {
                page.updateTodo(spaceId, todoId, todoField.text.trim())
            } else if (kind === "todo") {
                page.createTodo(spaceId, todoField.text.trim(),
                                todoParentOverride.length > 0
                                    ? todoParentOverride
                                    : page.currentParentId(page.todoPath),
                                todoAsList)
            } else if (kind === "bookmark" && bookmarkId.length > 0) {
                page.updateBookmark(spaceId, bookmarkId,
                                    bookmarkTitleField.text.trim(),
                                    bookmarkIsFolder ? "" : bookmarkUrlField.text.trim(),
                                    bookmarkIsFolder)
            } else if (kind === "bookmark") {
                page.createBookmark(spaceId,
                                    bookmarkTitleField.text.trim(),
                                    bookmarkIsFolder ? "" : bookmarkUrlField.text.trim(),
                                    bookmarkIsFolder,
                                    page.currentParentId(page.bookmarkPath))
            } else if (habitId.length > 0) {
                page.updateHabit(spaceId, habitId, habitNameField.text.trim(),
                                 habitRequirement())
            } else {
                page.createHabit(spaceId, habitNameField.text.trim(),
                                 habitRequirement())
            }
            visible = false
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 56
            spacing: 24

            Label {
                text: {
                    if (newItemPanel.kind === "habit") {
                        return newItemPanel.habitId.length > 0
                            ? "Edit habit"
                            : "New habit in " + newItemPanel.destination
                    }
                    if (newItemPanel.kind === "bookmark") {
                        if (newItemPanel.bookmarkId.length > 0) {
                            return newItemPanel.bookmarkIsFolder ? "Edit folder"
                                                                 : "Edit bookmark"
                        }
                        return (newItemPanel.bookmarkIsFolder ? "New folder in "
                                                              : "New bookmark in ")
                               + newItemPanel.destination
                    }
                    if (newItemPanel.todoId.length > 0) {
                        return newItemPanel.todoIsList ? "Edit list" : "Edit todo"
                    }
                    if (newItemPanel.todoParentOverride.length > 0) {
                        return "New sub-todo under " + newItemPanel.destination
                    }
                    return (newItemPanel.todoAsList ? "New list in "
                                                    : "New todo in ")
                           + newItemPanel.destination
                }
                font.pixelSize: 40
                font.bold: true
                color: "black"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            PanelField {
                id: todoField
                visible: newItemPanel.kind === "todo"
            }

            Button {
                visible: newItemPanel.kind === "todo"
                         && newItemPanel.todoId.length === 0
                         && newItemPanel.todoParentOverride.length === 0
                Layout.alignment: Qt.AlignLeft
                onClicked: newItemPanel.todoAsList = !newItemPanel.todoAsList
                contentItem: Text {
                    text: newItemPanel.todoAsList ? "Make a todo instead"
                                                  : "Make a list instead"
                    font.pixelSize: 26
                    color: "black"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "white"
                    border.color: "black"
                    border.width: 2
                    radius: 6
                }
                padding: 16
            }

            PanelLabel {
                text: newItemPanel.bookmarkIsFolder ? "Folder name" : "Title"
                visible: newItemPanel.kind === "bookmark"
            }
            PanelField {
                id: bookmarkTitleField
                visible: newItemPanel.kind === "bookmark"
            }
            PanelLabel {
                text: "Link"
                visible: newItemPanel.kind === "bookmark" && !newItemPanel.bookmarkIsFolder
            }
            PanelField {
                id: bookmarkUrlField
                visible: newItemPanel.kind === "bookmark" && !newItemPanel.bookmarkIsFolder
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            }
            Button {
                visible: newItemPanel.kind === "bookmark"
                         && newItemPanel.bookmarkId.length === 0
                Layout.alignment: Qt.AlignLeft
                onClicked: newItemPanel.bookmarkIsFolder = !newItemPanel.bookmarkIsFolder
                contentItem: Text {
                    text: newItemPanel.bookmarkIsFolder ? "Make a bookmark instead"
                                                        : "Make a folder instead"
                    font.pixelSize: 26
                    color: "black"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "white"
                    border.color: "black"
                    border.width: 2
                    radius: 6
                }
                padding: 16
            }

            PanelLabel {
                text: "Name"
                visible: newItemPanel.kind === "habit"
            }
            PanelField {
                id: habitNameField
                visible: newItemPanel.kind === "habit"
            }
            PanelLabel {
                text: "Repeats"
                visible: newItemPanel.kind === "habit"
            }
            RowLayout {
                visible: newItemPanel.kind === "habit"
                Layout.fillWidth: true
                spacing: 16

                ModeButton { mode: "everyday"; labelText: "Everyday" }
                ModeButton { mode: "week"; labelText: "Days per week" }
                ModeButton { mode: "fortnight"; labelText: "Days per 14 days" }
                ModeButton { mode: "custom"; labelText: "Custom" }
            }

            Stepper {
                visible: newItemPanel.kind === "habit"
                Layout.fillWidth: true
                label: "Required days"
                value: newItemPanel.habitRequiredDays
                editable: !newItemPanel.habitIsEveryday
                minimum: 1
                maximum: newItemPanel.habitWindowDays
                onStepped: (next) => newItemPanel.habitRequiredDays = next
            }

            Stepper {
                visible: newItemPanel.kind === "habit"
                Layout.fillWidth: true
                label: "Window days"
                value: newItemPanel.habitWindowDays
                editable: newItemPanel.habitMode === "custom"
                minimum: 1
                maximum: 365
                onStepped: (next) => newItemPanel.setWindowDays(next)
            }

            Stepper {
                visible: newItemPanel.kind === "habit"
                Layout.fillWidth: true
                label: "Completions per day"
                value: newItemPanel.habitRequired
                minimum: 1
                maximum: 99
                onStepped: (next) => newItemPanel.habitRequired = next
            }

            PanelLabel {
                text: "Window starts"
                visible: newItemPanel.kind === "habit" && !newItemPanel.habitIsEveryday
            }
            RowLayout {
                visible: newItemPanel.kind === "habit" && !newItemPanel.habitIsEveryday
                Layout.fillWidth: true
                spacing: 20

                Label {
                    text: Qt.formatDate(newItemPanel.habitAnchor, "ddd d MMM yyyy")
                    font.pixelSize: 30
                    font.bold: true
                    color: "black"
                    Layout.preferredWidth: 470
                }

                StepButton { symbol: "-7"; onClicked: newItemPanel.shiftAnchor(-7) }
                StepButton { symbol: "-1"; onClicked: newItemPanel.shiftAnchor(-1) }
                StepButton { symbol: "+1"; onClicked: newItemPanel.shiftAnchor(1) }
                StepButton { symbol: "+7"; onClicked: newItemPanel.shiftAnchor(7) }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                spacing: 16

                Item { Layout.fillWidth: true }

                Button {
                    onClicked: newItemPanel.visible = false
                    contentItem: Text {
                        text: "Cancel"
                        font.pixelSize: 28
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 6
                    }
                    padding: 20
                }

                Button {
                    enabled: newItemPanel.canSubmit
                    onClicked: newItemPanel.submit()
                    contentItem: Text {
                        text: newItemPanel.isEdit ? "Save" : "Add"
                        font.pixelSize: 28
                        font.bold: true
                        color: "black"
                        opacity: parent.enabled ? 1.0 : 0.35
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 3
                        radius: 6
                    }
                    padding: 20
                }
            }
        }
    }

    Rectangle {
        id: settingsPanel
        anchors.fill: parent
        color: "white"
        visible: false
        z: 100

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 56
            spacing: 28

            Label {
                text: "Settings"
                font.pixelSize: 40
                font.bold: true
                color: "black"
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: "Ask before saving handwritten todos"
                        font.pixelSize: 30
                        font.bold: true
                        color: "black"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: "When you circle handwriting in any notebook, choose the "
                              + "space and list it's saved to and edit the recognised "
                              + "text first. When off, it's saved straight to your "
                              + "active space."
                        font.pixelSize: 24
                        color: "black"
                        opacity: 0.6
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Button {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 76
                    onClicked: page.setConfirmNotebookTodos(!page.confirmNotebookTodos)
                    contentItem: Text {
                        text: page.confirmNotebookTodos ? "On" : "Off"
                        font.pixelSize: 28
                        font.bold: true
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: page.confirmNotebookTodos ? 5 : 2
                        radius: 8
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#d0d0d0" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: "Show Saver in the file browser sidebar"
                        font.pixelSize: 30
                        font.bold: true
                        color: "black"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: "Adds a Saver row under Import files, for opening the "
                              + "app without going through AppLoad's own launcher. "
                              + "Takes a few seconds to appear or disappear after "
                              + "changing this."
                        font.pixelSize: 24
                        color: "black"
                        opacity: 0.6
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Button {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 76
                    onClicked: page.setShowInSidebar(!page.showInSidebar)
                    contentItem: Text {
                        text: page.showInSidebar ? "On" : "Off"
                        font.pixelSize: 28
                        font.bold: true
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: page.showInSidebar ? 5 : 2
                        radius: 8
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#d0d0d0" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: "Default space for handwritten todos"
                        font.pixelSize: 30
                        font.bold: true
                        color: "black"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: page.notebookDefaultSpaceId.length > 0
                              ? page.notebookDefaultSpaceName
                              : "Your active space"
                        font.pixelSize: 26
                        color: "black"
                        opacity: 0.7
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Button {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 76
                    onClicked: settingsPicker.openFor("space")
                    contentItem: Text {
                        text: "Choose"
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 8
                    }
                }

                Button {
                    visible: page.notebookDefaultSpaceId.length > 0
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 76
                    onClicked: page.clearNotebookDefaultSpace()
                    contentItem: Text {
                        text: "Clear"
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 8
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 20
                opacity: page.notebookDefaultSpaceId.length > 0 ? 1.0 : 0.4

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: "Default list"
                        font.pixelSize: 30
                        font.bold: true
                        color: "black"
                    }
                    Label {
                        text: page.notebookDefaultSpaceId.length === 0
                              ? "Choose a default space first"
                              : (page.notebookDefaultListId.length > 0
                                 ? page.notebookDefaultListName : "Top level")
                        font.pixelSize: 26
                        color: "black"
                        opacity: 0.7
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Button {
                    enabled: page.notebookDefaultSpaceId.length > 0
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 76
                    onClicked: settingsPicker.openFor("list")
                    contentItem: Text {
                        text: "Choose"
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 8
                    }
                }

                Button {
                    visible: page.notebookDefaultListId.length > 0
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 76
                    onClicked: page.clearNotebookDefaultList()
                    contentItem: Text {
                        text: "Clear"
                        font.pixelSize: 26
                        color: "black"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 8
                    }
                }
            }

            Item { Layout.preferredHeight: 20 }

            Button {
                onClicked: settingsPanel.visible = false
                contentItem: Text {
                    text: "Done"
                    font.pixelSize: 28
                    font.bold: true
                    color: "black"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "white"
                    border.color: "black"
                    border.width: 3
                    radius: 6
                }
                padding: 20
                Layout.alignment: Qt.AlignLeft
            }
        }
    }

    Rectangle {
        id: settingsPicker

        property string mode: ""

        z: 200
        visible: mode.length > 0
        anchors.fill: parent
        color: "white"

        function openFor(which) {
            settingsPicker.mode = which
        }

        function optionsModel() {
            if (settingsPicker.mode === "space") return page.spaces
            if (settingsPicker.mode === "list") {
                var options = [{ id: "", title: "Top level" }]
                return options.concat(page.topLevelLists(page.notebookDefaultSpaceId))
            }
            return []
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 56
            spacing: 20

            Label {
                text: settingsPicker.mode === "space" ? "Default space" : "Default list"
                font.pixelSize: 40
                font.bold: true
                color: "black"
                Layout.fillWidth: true
            }

            SaverScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: settingsPicker.optionsModel()

                delegate: Item {
                    width: ListView.view.width
                    height: page.rowHeight

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (settingsPicker.mode === "space") {
                                page.setNotebookDefaultSpace(modelData.id, modelData.name)
                            } else {
                                page.setNotebookDefaultList(modelData.id, modelData.title)
                            }
                            settingsPicker.mode = ""
                        }
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8
                        text: settingsPicker.mode === "space" ? modelData.name : modelData.title
                        font.pixelSize: page.titleSize
                        color: "black"
                        elide: Text.ElideRight
                    }

                    RowSeparator {}
                }
            }

            Button {
                onClicked: settingsPicker.mode = ""
                contentItem: Text {
                    text: "Back"
                    font.pixelSize: 28
                    color: "black"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "white"
                    border.color: "black"
                    border.width: 2
                    radius: 6
                }
                padding: 20
                Layout.alignment: Qt.AlignLeft
            }
        }
    }

}
