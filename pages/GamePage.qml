// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Tacit.Kit
import ".."
import "../board"
import "../lib/Color.js" as Color

// The game page: the header with the page's tools, the board large and left, the moves at the right in a
// narrow column. The board keeps the room it needs; the moves column takes what is left. A promotion is
// asked where it lands: a strip of the four pieces rises over the square, Escape or a press elsewhere
// takes it back.
Item {
    id: page

    readonly property int movesWidth: Kit.tokens.width.rail
    readonly property bool compact: width < height
    property bool eventsExpanded: false
    // the promotion waiting to be answered: {from, to}, empty when there is none
    property var promotion: null

    function chooseMove(from, to) {
        // a pawn to the last rank is four legal moves, one per piece: ask which one
        const options = Game.legalMoves(from).filter(m => m.to === to);
        if (options.length === 0)
            return;
        if (options[0].promotion !== undefined) {
            page.promotion = { "from": from, "to": to };
            return;
        }
        if (Game.makeMove(from, to) && Engine.ready)
            Engine.requestMove(Game.fen);
    }
    function answerPromotion(piece) {
        const asked = page.promotion;
        page.promotion = null;
        if (Game.makeMove(asked.from, asked.to, piece) && Engine.ready)
            Engine.requestMove(Game.fen);
    }
    function startNewGame() {
        Engine.cancelSearch();
        Game.newGame();
        Engine.newGame();
    }
    function undoMove() {
        Engine.cancelSearch();
        Game.undoToWhite();
        Engine.newGame();
    }

    // Escape takes the promotion back, from wherever the keyboard is
    Keys.onEscapePressed: page.promotion = null
    Component.onCompleted: Engine.start()

    Connections {
        target: Engine
        function onReadyChanged() {
            if (Engine.ready && Game.turn === "b" && !Game.over)
                Engine.requestMove(Game.fen);
        }
        function onMoveReady(from, to, promotion) {
            if (!Game.makeMove(from, to, promotion))
                Engine.fail("returned an illegal move");
        }
    }

    Item {
        id: header
        width: parent.width
        height: Kit.tokens.height.header + 1

        TacitText {
            anchors {
                left: parent.left
                leftMargin: Kit.tokens.space.l
                verticalCenter: parent.verticalCenter
            }
            text: "Chess"
            size: "headline"
            cut: "display"
            weight: "strong"
        }

        Row {
            anchors {
                right: parent.right
                rightMargin: Kit.tokens.space.xl
                verticalCenter: parent.verticalCenter
            }
            spacing: Kit.tokens.space.xl

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "undo"
                size: Kit.tokens.icon.nav
                label: "Undo move"
                tip: "Undo move"
                enabled: Game.history.length > 0 && !Engine.thinking
                onActivated: page.undoMove()
            }
            Slab {
                anchors.verticalCenter: parent.verticalCenter
                text: "New game"
                confirm: "Start a new game?"
                onActivated: page.startNewGame()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "swap_horiz"
                size: Kit.tokens.icon.nav
                label: "Flip board"
                tip: "Flip board"
                onActivated: board.flipped = !board.flipped
            }

        }

        Rectangle {
            x: Kit.tokens.space.l
            y: Kit.tokens.height.header
            width: parent.width - Kit.tokens.space.l
            height: 1
            color: Kit.tokens.hairline
        }
    }

    Item {
        id: boardArea
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        Board {
            id: board
            anchors.centerIn: parent
            // whole cells inside the page's margins: the squares never come out ragged at the edge
            side: Math.max(0, Math.floor((Math.min(boardArea.width, boardArea.height) - 2 * Kit.tokens.space.xl) / 8) * 8)
            fen: Game.fen
            lastFrom: Game.lastFrom
            lastTo: Game.lastTo
            check: Game.check
            picksUp: Engine.available ? "w" : "wb"
            onMoveChosen: (from, to) => page.chooseMove(from, to)
        }

        // the promotion picker: the four pieces over the square the pawn reached, the page's overlay
        // ground so the board under it does not show through. It opens at the square, the whole strip
        // kept on the board; the queen is the first stop, Escape or a press elsewhere takes it back.
        Item {
            id: picker
            anchors.fill: parent
            visible: page.promotion !== null

            onVisibleChanged: {
                if (!visible)
                    return;
                place();
                choices.itemAt(0).forceActiveFocus();
            }
            function place() {
                if (!page.promotion)
                    return;
                const file = "abcdefgh".indexOf(page.promotion.to[0]);
                const rank = Number(page.promotion.to[1]);
                const displayCol = board.flipped ? 7 - file : file;
                const displayRow = board.flipped ? rank - 1 : 8 - rank;
                const px = board.x + displayCol * board.cell;
                const py = board.y + displayRow * board.cell;
                strip.width = board.cell + 2 * Kit.tokens.space.xs;
                strip.height = 4 * board.cell + 5 * Kit.tokens.space.xs;
                strip.x = Math.max(board.x, Math.min(px - Kit.tokens.space.xs, board.x + board.width - strip.width));
                strip.y = py > board.y + board.height / 2 ? py - strip.height + board.cell : py;
            }

            // a press elsewhere does not go through to the board while the picker is open
            MouseArea {
                anchors.fill: parent
                onPressed: page.promotion = null
            }

            Rectangle {
                id: strip
                radius: Kit.tokens.radius.row
                color: Kit.tokens.overlay

                Column {
                    x: Kit.tokens.space.xs
                    y: Kit.tokens.space.xs
                    spacing: Kit.tokens.space.xs

                    Repeater {
                        id: choices
                        model: ["q", "r", "b", "n"]

                        delegate: Item {
                            id: choice
                            required property string modelData
                            width: board.cell
                            height: board.cell
                            activeFocusOnTab: true

                            Rectangle {
                                anchors.fill: parent
                                radius: Kit.tokens.radius.row
                                color: choiceHover.hovered || choice.activeFocus
                                    ? Color.mix(Kit.tokens.overlay, Kit.tokens.inkMain, Kit.tokens.wash.currentHover)
                                    : "transparent"
                            }
                            Image {
                                anchors.fill: parent
                                source: board.pieceSource(Game.turn === "w" ? choice.modelData.toUpperCase() : choice.modelData)
                                sourceSize: Qt.size(board.cell, board.cell)
                                fillMode: Image.PreserveAspectFit
                            }
                            HoverHandler { id: choiceHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.answerPromotion(choice.modelData) }
                            Keys.onReturnPressed: page.answerPromotion(choice.modelData)
                            Keys.onEnterPressed: page.answerPromotion(choice.modelData)
                            Keys.onSpacePressed: page.answerPromotion(choice.modelData)
                            Keys.onEscapePressed: page.promotion = null
                        }
                    }
                }
            }
        }
    }

    Item {
        id: movesColumn
        visible: !page.compact
        anchors {
            top: header.bottom
            right: parent.right
            bottom: parent.bottom
        }
        width: page.movesWidth

        Item {
            id: statusRow
            width: parent.width
            y: board.y
            height: Math.max(gameStatus.implicitHeight, eventsToggle.implicitHeight)

            Item {
                id: statusButton
                anchors {
                    left: parent.left
                    right: eventsToggle.left
                    rightMargin: Kit.tokens.space.xs
                    verticalCenter: parent.verticalCenter
                }
                implicitHeight: gameStatus.implicitHeight
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: gameStatus.text
                Accessible.description: page.eventsExpanded ? "Hide game events" : "Show game events"
                Accessible.onPressAction: page.eventsExpanded = !page.eventsExpanded

                Rectangle {
                    anchors.fill: parent
                    radius: Kit.tokens.radius.row
                    color: Kit.tokens.inkMain
                    opacity: statusHover.hovered ? Kit.tokens.wash.hoverSmall : 0
                    Behavior on opacity { NumberAnimation { duration: Kit.ms(Kit.motion("tone").ms) } }
                }
                FocusRing { shown: statusButton.activeFocus && Kit.focusVisible; corner: Kit.tokens.radius.row }
                HoverHandler { id: statusHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.eventsExpanded = !page.eventsExpanded }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        page.eventsExpanded = !page.eventsExpanded;
                        event.accepted = true;
                    }
                }

                TacitText {
                    id: gameStatus
                    anchors.fill: parent
                    text: Game.over ? Game.resultText
                        : Game.check ? ((Game.turn === "w" ? "Black" : "White") + " checked "
                            + (Game.turn === "w" ? "White" : "Black"))
                        : Engine.thinking ? "Computer is thinking"
                        : Engine.available ? (Game.turn === "w" ? "Your move" : "Computer to move")
                        : Engine.status
                    ink: Game.over || Game.check ? "main" : "sec"
                    wrapMode: Text.WordWrap
                }
            }
            IconButton {
                id: eventsToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                symbol: page.eventsExpanded ? "expand_less" : "expand_more"
                size: Kit.tokens.icon.nav
                label: page.eventsExpanded ? "Show current event" : "Show all game events"
                tip: label
                checked: page.eventsExpanded
                checkable: true
                onActivated: page.eventsExpanded = !page.eventsExpanded
            }
        }
        Item {
            id: eventPanel
            x: 0
            y: statusRow.y + statusRow.height
            width: parent.width
            height: page.eventsExpanded ? Math.max(0, movesColumn.height - y) : 0
            clip: true
            opacity: page.eventsExpanded ? 1 : 0
            visible: height > 0
            Behavior on height {
                NumberAnimation { duration: Kit.ms(Kit.motion("arriveSmall").ms) }
            }
            Behavior on opacity {
                NumberAnimation { duration: Kit.ms(Kit.motion("fadeFast").ms) }
            }

            RowList {
                id: eventList
                anchors.fill: parent
                label: "Game events"
                model: Game.eventHistory
                delegate: ListRow {
                    required property var modelData
                    required property int index
                    width: eventList.rowWidth
                    focusable: false
                    lead: String(index + 1)
                    leadFigures: 3
                    name: modelData.text
                }
            }
        }
    }
}
