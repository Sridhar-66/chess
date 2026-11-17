// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Tacit.Kit
import ".."
import "../board"
import "../lib/Color.js" as Color

// The game page: the board on the left, and on the right the game's panel — whose move it is, big at the
// top, the pieces each side has taken, the moves, and the three actions along the bottom. The window
// snapped to one side of the screen has no room for both, so then the board is alone; a swipe up brings
// the window back to the default view. A promotion is asked where it lands: a strip of the four pieces
// rises over the square, Escape or a press elsewhere takes it back.
Item {
    id: page

    // the window the page lives in, given by the shell that loaded it
    property var appWindow: null

    // the default view fills the screen: the board on the left, the panel on the right. a window on one
    // side of the screen is narrower than the screen, and then the board is alone
    readonly property real screenWidth: appWindow && appWindow.screen ? appWindow.screen.width : 0
    readonly property bool sided: screenWidth > 0 && width < screenWidth * 0.65
    readonly property bool showPanel: !sided

    readonly property int panelWidth: 340
    readonly property int panelPad: Kit.tokens.space.l
    readonly property int boardGutter: Kit.tokens.space.l
    // the board is square: it takes the room the shorter side allows, in whole squares
    readonly property real boardSide: {
        const roomWidth = showPanel
            ? content.width - panelWidth - panelPad - boardGutter
            : content.width - boardGutter;
        const roomHeight = content.height - boardGutter;
        return Math.max(0, Math.floor(Math.min(roomWidth, roomHeight) / 8) * 8);
    }
    // the promotion waiting to be answered: {from, to}, empty when there is none
    property var promotion: null

    // the side the person plays; the engine takes the other one. The board reads from the person's side.
    property string humanSide: "w"
    function playOtherSide() {
        Engine.cancelSearch();
        page.humanSide = page.humanSide === "w" ? "b" : "w";
        if (!Game.over && Game.turn !== page.humanSide && Engine.ready)
            Engine.requestMove(Game.fen);
    }

    // what each side has taken, in the order the pieces are worth: White's captures are Black's pieces
    readonly property var captures: {
        const history = Game.history;
        const byWhite = [];
        const byBlack = [];
        for (const move of history) {
            if (!move.captured)
                continue;
            if (move.color === "w")
                byWhite.push(move.captured);
            else
                byBlack.push(move.captured.toUpperCase());
        }
        const order = "pnbrq";
        const value = piece => order.indexOf(piece.toLowerCase());
        byWhite.sort((a, b) => value(a) - value(b));
        byBlack.sort((a, b) => value(a) - value(b));
        return { "byWhite": byWhite, "byBlack": byBlack };
    }

    // the moves in pairs: {number, name (White), aside (Black)}
    readonly property var moveRows: {
        const history = Game.history;
        const rows = [];
        for (let i = 0; i < history.length; i += 2) {
            rows.push({
                "number": String(i / 2 + 1),
                "name": history[i].san,
                "aside": i + 1 < history.length ? history[i + 1].san : ""
            });
        }
        return rows;
    }

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
        if (Game.turn !== page.humanSide && Engine.ready)
            Engine.requestMove(Game.fen);
    }
    function undoMove() {
        Engine.cancelSearch();
        Game.undoToTurn(page.humanSide);
        Engine.newGame();
        if (!Game.over && Game.turn !== page.humanSide && Engine.ready)
            Engine.requestMove(Game.fen);
    }
    // Escape takes the promotion back, from wherever the keyboard is
    Keys.onEscapePressed: page.promotion = null
    Component.onCompleted: Engine.start()

    Connections {
        target: Engine
        function onReadyChanged() {
            if (Engine.ready && Game.turn !== page.humanSide && !Game.over)
                Engine.requestMove(Game.fen);
        }
        function onMoveReady(from, to, promotion) {
            if (!Game.makeMove(from, to, promotion))
                Engine.fail("returned an illegal move");
        }
    }

    Connections {
        target: Game
        function onMoved() {
            // a new move joins the list at its end, where it is read
            Qt.callLater(() => moveList.view.positionViewAtEnd());
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

        Rectangle {
            x: Kit.tokens.space.l
            y: Kit.tokens.height.header
            width: parent.width - Kit.tokens.space.l
            height: 1
            color: Kit.tokens.hairline
        }
    }

    Item {
        id: content
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: Kit.tokens.space.l
            rightMargin: Kit.tokens.space.l
        }

        Item {
            id: boardArea
            x: showPanel ? 0 : Math.round((content.width - (page.boardSide + page.boardGutter)) / 2)
            y: 0
            width: page.boardSide + page.boardGutter
            height: content.height

            Board {
                id: board
                side: page.boardSide
                gutter: page.boardGutter
                x: page.boardGutter
                y: Math.round((boardArea.height - (page.boardSide + page.boardGutter)) / 2)
                fen: Game.fen
                lastFrom: Game.lastFrom
                lastTo: Game.lastTo
                check: Game.check
                picksUp: Engine.available ? page.humanSide : "wb"
                flipped: page.humanSide === "b"
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
            id: sidePanel
            visible: showPanel
            x: boardArea.x + boardArea.width + page.panelPad
            y: 0
            width: page.panelWidth
            height: content.height

            TacitText {
                id: statusText
                x: page.panelPad
                y: Kit.tokens.space.l
                width: sidePanel.width - 2 * page.panelPad
                text: Game.over ? Game.resultText
                    : Game.check ? ((Game.turn === "w" ? "Black" : "White") + " checked "
                        + (Game.turn === "w" ? "White" : "Black"))
                    : Engine.thinking ? "Computer is thinking"
                    : Engine.available
                        ? (Game.turn === page.humanSide ? "Your move" : "Computer to move")
                    : Engine.status
                size: "headline"
                cut: "display"
                weight: "medium"
                wrapMode: Text.WordWrap
            }

            Column {
                id: capturedBlock
                x: page.panelPad
                y: statusText.y + statusText.height + Kit.tokens.space.m
                width: sidePanel.width - 2 * page.panelPad
                spacing: Kit.tokens.space.s

                Column {
                    width: parent.width
                    spacing: Kit.tokens.space.xs
                    visible: page.captures.byWhite.length > 0

                    TacitText {
                        text: page.humanSide === "w" ? "You captured" : "Computer captured"
                        size: "fileText"
                        ink: "sec"
                        weight: "medium"
                    }
                    Flow {
                        width: parent.width
                        spacing: Kit.tokens.space.xs / 2

                        Repeater {
                            model: page.captures.byWhite
                            Image {
                                required property string modelData
                                width: Kit.tokens.icon.nav
                                height: Kit.tokens.icon.nav
                                source: board.pieceSource(modelData)
                                sourceSize: Qt.size(Kit.tokens.icon.nav, Kit.tokens.icon.nav)
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: Kit.tokens.space.xs
                    visible: page.captures.byBlack.length > 0

                    TacitText {
                        text: page.humanSide === "b" ? "You captured" : "Computer captured"
                        size: "fileText"
                        ink: "sec"
                        weight: "medium"
                    }
                    Flow {
                        width: parent.width
                        spacing: Kit.tokens.space.xs / 2

                        Repeater {
                            model: page.captures.byBlack
                            Image {
                                required property string modelData
                                width: Kit.tokens.icon.nav
                                height: Kit.tokens.icon.nav
                                source: board.pieceSource(modelData)
                                sourceSize: Qt.size(Kit.tokens.icon.nav, Kit.tokens.icon.nav)
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }
            }

            SectionHeading {
                id: movesHeading
                x: page.panelPad - Kit.tokens.space.l
                y: capturedBlock.y + capturedBlock.height + Kit.tokens.space.s
                text: "Moves"
            }

            RowList {
                id: moveList
                x: page.panelPad
                y: movesHeading.y + movesHeading.height
                width: sidePanel.width - 2 * page.panelPad
                height: Math.max(0, buttonBar.y - Kit.tokens.space.s - moveList.y)
                label: "Moves"
                model: page.moveRows

                delegate: ListRow {
                    required property var modelData
                    required property int index
                    width: moveList.rowWidth
                    focusable: false
                    selected: moveList.isSelected(index)
                    ring: moveList.ringAt(index)
                    joinAbove: moveList.isSelected(index - 1)
                    joinBelow: moveList.isSelected(index + 1)
                    lead: modelData.number
                    leadFigures: 2
                    name: modelData.name
                    aside: modelData.aside
                    onClicked: modifiers => moveList.clickAt(index, modifiers)
                }
            }

            Item {
                id: buttonBar
                x: page.panelPad
                width: sidePanel.width - 2 * page.panelPad
                height: Kit.tokens.height.action
                y: sidePanel.height - height - Kit.tokens.space.l

                Row {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Kit.tokens.space.s

                    Slab {
                        text: "New game"
                        tone: "default"
                        confirm: "Start a new game?"
                        onActivated: page.startNewGame()
                    }
                    Slab {
                        text: "Undo"
                        waiting: Game.history.length === 0 || Engine.thinking
                        onActivated: page.undoMove()
                    }
                    Slab {
                        text: page.humanSide === "w" ? "Play black" : "Play white"
                        onActivated: page.playOtherSide()
                    }
                }
            }
        }
    }
}
