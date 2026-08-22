import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: page

    property string userCode: ""
    property string verificationUrl: ""
    property int qrSize: 0
    property string qrModules: ""
    property string statusText: ""
    property string errorText: ""

    signal retry()
    signal closeApp()

    background: Rectangle { color: "white" }

    onQrModulesChanged: qrCanvas.requestPaint()

    function formattedCode() {
        if (userCode.length !== 8) return userCode
        return userCode.substring(0, 4) + "-" + userCode.substring(4)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 56
        spacing: 28

        Label {
            text: "Link your Saver account"
            font.pixelSize: 64
            font.bold: true
            color: "black"
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: "Scan this code, or open " + page.verificationUrl
            font.pixelSize: 32
            color: "black"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
        }

        Canvas {
            id: qrCanvas
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 640
            Layout.preferredHeight: 640
            visible: page.qrSize > 0

            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "white"
                ctx.fillRect(0, 0, width, height)
                if (page.qrSize <= 0 || page.qrModules.length === 0) return

                var quiet = 2
                var total = page.qrSize + quiet * 2
                var scale = Math.floor(Math.min(width, height) / total)
                if (scale < 1) scale = 1
                var origin = (width - scale * total) / 2

                ctx.fillStyle = "black"
                for (var y = 0; y < page.qrSize; y++) {
                    for (var x = 0; x < page.qrSize; x++) {
                        if (page.qrModules.charAt(y * page.qrSize + x) === "1") {
                            ctx.fillRect(origin + (x + quiet) * scale,
                                         origin + (y + quiet) * scale,
                                         scale, scale)
                        }
                    }
                }
            }
        }

        Label {
            text: "Then enter this code:"
            font.pixelSize: 32
            color: "black"
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: page.formattedCode()
            font.pixelSize: 88
            font.bold: true
            font.letterSpacing: 6
            font.family: "monospace"
            color: "black"
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: page.statusText
            font.pixelSize: 28
            color: "black"
            visible: page.statusText.length > 0 && page.errorText.length === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Label {
            text: page.errorText
            font.pixelSize: 28
            color: "black"
            visible: page.errorText.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Button {
            text: "Start over"
            visible: page.errorText.length > 0
            onClicked: page.retry()
            Layout.alignment: Qt.AlignHCenter

            contentItem: Text {
                text: parent.text
                font.pixelSize: 28
                color: "black"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            padding: 20
        }

        Item { Layout.fillHeight: true }

        Button {
            text: "Close"
            onClicked: page.closeApp()
            Layout.alignment: Qt.AlignHCenter

            contentItem: Text {
                text: parent.text
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
