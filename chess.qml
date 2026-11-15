// SPDX-License-Identifier: GPL-3.0-or-later
//@ pragma AppId chess
//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Tacit.Kit

// Chess: play Stockfish on Tacit. The window is the app (the Music example's shape): FloatingWindow with
// WindowGround drawing, pages in pages/, the board and its pieces in board/. Run with  qs -p chess.qml.
FloatingWindow {
    id: window

    title: "Chess"
    implicitWidth: 1280
    implicitHeight: 820
    color: "transparent"

    Component.onCompleted: Kit.watchKeys(window)

    Item {
        id: app
        anchors.fill: parent
        focus: true

        WindowGround {}

        Loader {
            anchors.fill: parent
            source: "pages/GamePage.qml"
        }

        Notice {
            id: eventNotice
        }

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
                Game.undoToWhite();
                Engine.newGame();
            }
        }
    }
}
