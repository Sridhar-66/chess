// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Quickshell
import Tacit.Kit

FloatingWindow {
    id: window
    title: "Chess"
    implicitWidth: Quickshell.env("GRAB_W") ? Number(Quickshell.env("GRAB_W")) : 1280
    implicitHeight: Quickshell.env("GRAB_H") ? Number(Quickshell.env("GRAB_H")) : 820
    color: "transparent"

    Component.onCompleted: Kit.watchKeys(window)

    Item {
        id: app
        anchors.fill: parent
        focus: true

        WindowGround {}

        Loader {
            id: pageLoader
            anchors {
                fill: parent
                rightMargin: Quickshell.env("GRAB_NARROW") ? parent.width - 620 : 0
            }
            source: "pages/GamePage.qml"
            onLoaded: pageLoader.item.appWindow = window
        }

        Notice { id: eventNotice }

        Connections {
            target: Game
            function onEventOccurred(message, kind) {
                if (["check", "checkmate", "stalemate", "terminal", "castle"].includes(kind))
                    eventNotice.show(message, "Undo");
            }
        }

        Connections {
            target: eventNotice
            function onActivated() {
                Engine.cancelSearch();
                Game.undoToTurn("w");
                Engine.newGame();
            }
        }

        Timer {
            interval: 2500
            running: true
            onTriggered: app.grabToImage(result => {
                print("saved", result.saveToFile(Quickshell.env("GRAB_OUT") || "/tmp/opencode/chess-grab.png"));
                Qt.quit();
            })
        }
    }
}
