// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import Tacit.Kit
import ".."
import "../lib/Fen.js" as Fen
import "../lib/Color.js" as Mix

// The board and everything done on it: eight by eight squares from a FEN string, the pieces on them,
// picking a piece up by click or drag, the dots on its legal moves (a ring where a capture lands), the
// last move and a king in check marked, files and ranks in the corners of the edge squares. It reads
// its colours from the palette (the light square is the document's paper, the dark one the document's
// quieter ink walked a little way back towards it), so it sits well on every wallpaper. Flipped, rank 1
// and file h come to the bottom left.
Item {
    id: board

    property real side: 480
    property bool flipped: false
    property string fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    // the move just played, to mark it; empty before the first move
    property string lastFrom: ""
    property string lastTo: ""
    // the side to move is in check: its king is marked
    property bool check: false
    // which sides a human may pick up now ("w", "b" or "wb" while the engine is not playing)
    property string picksUp: "wb"
    // a move the person chose: a promotion is answered by the picker in the page
    signal moveChosen(string from, string to)

    readonly property var rows: Fen.rows(fen)
    readonly property real cell: side / 8
    readonly property string turnSide: fen.split(" ")[1] ?? "w"

    // the two square colours, from the palette
    readonly property color lightSquare: Kit.tokens.paper
    readonly property color darkSquare: Mix.mix(Kit.tokens.paperInkSec, Kit.tokens.paper, 0.25)

    // the marks on the squares, all mixed from the palette onto the square they sit on: the picked-up
    // piece and its dots are the app's mark (the paper mark), the last move a lighter wash of it, a
    // king in check the risk colour
    readonly property color mark: Kit.tokens.paperMark
    function marked(squareColor, how) {
        return Mix.mix(squareColor, mark, how);
    }
    readonly property color checkMark: Kit.tokens.risk

    // where a king stands: the one square of its side's piece letter in the FEN
    function kingSquare(color) {
        const wanted = color === "w" ? "K" : "k";
        for (let i = 0; i < 64; i++) {
            const r = Math.floor(i / 8), c = i % 8;
            if (rows[r][c] === wanted)
                return Fen.squareOf(i);
        }
        return "";
    }
    // the king of the side to move, when that side is in check
    readonly property string checkSquare: check ? kingSquare(turnSide) : ""

    readonly property int glideMs: Kit.ms(Kit.motion("arriveSmall").ms)
    property var beforeRows: []
    property var movers: []
    property var fades: []
    property var hiddenSquares: []
    property bool skipNextMoveAnimation: false

    onRowsChanged: board.applyPosition()
    onFlippedChanged: board.endMotion()
    onCellChanged: board.endMotion()

    function copyRows(source) {
        const out = [];
        for (let i = 0; i < source.length; i++)
            out.push(source[i]);
        return out;
    }
    function pieceAtRow(rows, square) {
        if (!/^[a-h][1-8]$/.test(square))
            return ".";
        const i = Fen.indexAt(square);
        return rows[Math.floor(i / 8)][i % 8];
    }
    function cellPoint(square) {
        const file = Fen.files.indexOf(square[0]);
        const rank = Number(square[1]);
        return Qt.point((board.flipped ? 7 - file : file) * board.cell,
                        (board.flipped ? rank - 1 : 8 - rank) * board.cell);
    }
    function sideOf(piece) {
        return piece === piece.toUpperCase() ? "w" : "b";
    }
    function glide(piece, from, to) {
        const a = cellPoint(from), b = cellPoint(to);
        return { "piece": piece, "fromX": a.x, "fromY": a.y, "toX": b.x, "toY": b.y };
    }
    function fade(piece, square) {
        const p = cellPoint(square);
        return { "piece": piece, "x": p.x, "y": p.y };
    }
    function endMotion() {
        movers = [];
        fades = [];
        hiddenSquares = [];
    }
    function applyPosition() {
        const next = board.rows;
        if (board.beforeRows.length !== 8) {
            board.beforeRows = board.copyRows(next);
            return;
        }
        const old = board.beforeRows;
        board.beforeRows = board.copyRows(next);
        board.endMotion();
        const skip = board.skipNextMoveAnimation;
        board.skipNextMoveAnimation = false;
        const from = board.lastFrom, to = board.lastTo;
        if (skip || from === "" || to === "")
            return;
        const piece = board.pieceAtRow(old, from);
        if (piece === "." || board.pieceAtRow(next, from) !== "." || board.pieceAtRow(next, to) === ".")
            return;

        const moves = [board.glide(piece, from, to)];
        const hidden = [to];

        if (piece.toLowerCase() === "k"
                && Math.abs(Fen.files.indexOf(to[0]) - Fen.files.indexOf(from[0])) === 2) {
            const rank = to[1];
            const kingSide = Fen.files.indexOf(to[0]) > Fen.files.indexOf(from[0]);
            const rookFrom = (kingSide ? "h" : "a") + rank;
            const rookTo = (kingSide ? "f" : "d") + rank;
            const rook = board.pieceAtRow(old, rookFrom);
            if (rook !== ".") {
                moves.push(board.glide(rook, rookFrom, rookTo));
                hidden.push(rookTo);
            }
        }

        const leaving = [];
        const captured = board.pieceAtRow(old, to);
        if (captured !== "." && board.sideOf(captured) !== board.sideOf(piece))
            leaving.push(board.fade(captured, to));
        else if (piece.toLowerCase() === "p" && from[0] !== to[0]) {
            const taken = to[0] + from[1];
            const pawn = board.pieceAtRow(old, taken);
            if (pawn !== ".")
                leaving.push(board.fade(pawn, taken));
        }

        board.movers = moves;
        board.fades = leaving;
        board.hiddenSquares = hidden;
        if (board.glideMs > 0)
            motionTimer.restart();
        else
            board.endMotion();
    }

    Timer {
        id: motionTimer
        interval: board.glideMs + 60
        onTriggered: board.endMotion()
    }

    Component.onCompleted: board.beforeRows = board.copyRows(board.rows)

    implicitWidth: side
    implicitHeight: side

    // piece art from the cburnett set (the Lichess default), the same SVGs for both sides with the
    // black pieces laid over white detail lines, in pieces/
    function pieceSource(p) {
        return p === "." ? "" : Qt.resolvedUrl("pieces/" + (p === p.toUpperCase() ? "w" : "b") + p.toUpperCase() + ".svg");
    }

    // the square a point on the board is: the files and ranks read through the flip
    function squareAt(x, y) {
        const col = Math.max(0, Math.min(7, Math.floor(x / cell)));
        const row = Math.max(0, Math.min(7, Math.floor(y / cell)));
        return Fen.files[flipped ? 7 - col : col] + String(flipped ? row + 1 : 8 - row);
    }

    // a piece this board lets a person pick up: the side to move's, among the sides a human plays
    function canPickUp(square) {
        const p = Game.pieceAt(square);
        return Game.canPick(square) && picksUp.indexOf(p.color) >= 0;
    }

    // what may be picked up and what it may reach
    property string selected: ""
    property var targets: []

    function select(square) {
        selected = square;
        targets = Game.legalMoves(square);
    }
    function deselect() {
        select("");
    }
    function isTarget(square) {
        return targets.some(m => m.to === square);
    }

    function pieceFen(square) {
        if (typeof square !== "string" || !/^[a-h][1-8]$/.test(square))
            return ".";
        const i = Fen.indexAt(square);
        const r = flipped ? 7 - Math.floor(i / 8) : Math.floor(i / 8);
        const c = flipped ? 7 - (i % 8) : i % 8;
        return rows[r][c];
    }

    // dragging: the piece leaves its square and follows the pointer in the drag layer
    property bool dragging: false
    property string dragFrom: ""
    property point dragPoint: Qt.point(0, 0)

    function startDrag(square, x, y) {
        dragging = true;
        dragFrom = square;
        dragPoint = Qt.point(x, y);
        select(square);
    }
    function stopDrag() {
        dragging = false;
        dragFrom = "";
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: {
            const at = board.squareAt(pointer.mouseX, pointer.mouseY);
            if (board.dragging)
                return Qt.ClosedHandCursor;
            if (board.selected !== "" && board.isTarget(at))
                return Qt.PointingHandCursor;
            if (canPickUp(at))
                return Qt.PointingHandCursor;
            return Qt.ArrowCursor;
        }

        onPressed: mouse => {
            const at = board.squareAt(mouse.x, mouse.y);
            if (board.selected !== "" && board.isTarget(at)) {
                board.moveChosen(board.selected, at);
                board.deselect();
                return;
            }
            if (canPickUp(at)) {
                if (board.selected === at)
                    board.deselect();
                else
                    board.select(at);
                board.dragStartPoint = Qt.point(mouse.x, mouse.y);
                board.pressSquare = at;
                return;
            }
            board.deselect();
        }
        onPositionChanged: mouse => {
            // a pick up follows the pointer only once it has gone somewhere, so a plain click stays a click
            if (pointer.pressed && board.pressSquare !== "" && !board.dragging
                && Math.abs(mouse.x - board.dragStartPoint.x) + Math.abs(mouse.y - board.dragStartPoint.y) > 6)
                board.startDrag(board.pressSquare, mouse.x, mouse.y);
            if (board.dragging)
                board.dragPoint = Qt.point(mouse.x, mouse.y);
        }
        onReleased: mouse => {
            const at = board.squareAt(mouse.x, mouse.y);
            if (board.dragging) {
                board.stopDrag();
                if (at !== board.pressSquare && at !== "") {
                    if (board.isTarget(at)) {
                        const choices = Game.legalMoves(board.pressSquare).filter(m => m.to === at);
                        if (choices.length > 0 && choices[0].promotion === undefined)
                            board.skipNextMoveAnimation = true;
                        board.moveChosen(board.pressSquare, at);
                        board.deselect();
                    } else
                        board.select(board.pressSquare);
                }
            }
            board.pressSquare = "";
        }
    }
    // state the pointer handler works with
    property point dragStartPoint: Qt.point(0, 0)
    property string pressSquare: ""

    // the dragged piece follows the pointer, a little under it so it reads as held
    Image {
        visible: board.dragging
        source: board.pieceSource(board.pieceFen(board.dragFrom))
        sourceSize: Qt.size(board.cell, board.cell)
        fillMode: Image.PreserveAspectFit
        x: board.dragPoint.x - width / 2
        y: board.dragPoint.y - height * 0.85
        width: board.cell
        height: board.cell
        z: 10
    }

    Grid {
        id: squares
        columns: 8
        rows: 8

        Repeater {
            model: 64

            Item {
                id: cell
                required property int index
                readonly property int row: Math.floor(index / 8)
                readonly property int col: index % 8
                readonly property string square:
                    Fen.files[board.flipped ? 7 - col : col] + String(board.flipped ? row + 1 : 8 - row)
                readonly property string piece: board.pieceFen(square)
                readonly property bool light: (row + col) % 2 === 0
                readonly property color squareColor: light ? board.lightSquare : board.darkSquare
                readonly property bool isLast: square === board.lastFrom || square === board.lastTo
                readonly property bool isChecked: square === board.checkSquare
                readonly property bool isSelected: square === board.selected
                readonly property bool isTarget: board.isTarget(square)

                width: board.cell
                height: board.cell

                Rectangle {
                    anchors.fill: parent
                    color: cell.isChecked ? Mix.mix(cell.squareColor, board.checkMark, 0.45)
                        : cell.isSelected ? board.marked(cell.squareColor, 0.4)
                        : cell.isLast ? board.marked(cell.squareColor, 0.2)
                        : cell.squareColor
                    Behavior on color { ColorAnimation { duration: Kit.ms(Kit.motion("tone").ms) } }
                }

                // where the picked-up piece may go: a dot on a quiet square, a ring where a capture lands
                Rectangle {
                    anchors.centerIn: parent
                    visible: cell.isTarget
                    width: parent.width * (cell.piece === "." ? 0.28 : 0.86)
                    height: width
                    radius: width / 2
                    color: cell.piece === "." ? board.marked(cell.squareColor, 0.35)
                        : "transparent"
                    border.width: cell.piece === "." ? 0 : Math.max(2, parent.width * 0.07)
                    border.color: board.marked(cell.squareColor, 0.5)
                }

                Image {
                    anchors.fill: parent
                    visible: source != "" && !(board.dragging && board.dragFrom === cell.square)
                        && board.hiddenSquares.indexOf(cell.square) < 0
                    source: board.pieceSource(cell.piece)
                    sourceSize: Qt.size(board.cell, board.cell)
                    fillMode: Image.PreserveAspectFit
                }

                // the files and ranks, in the corners of the edge squares only
                TacitText {
                    visible: cell.col === 0
                    x: Kit.tokens.space.xs
                    y: Kit.tokens.space.xs
                    text: String(board.flipped ? cell.row + 1 : 8 - cell.row)
                    size: "meta"
                    color: cell.light ? Kit.tokens.paperInkSec
                        : Mix.mix(Kit.tokens.paperInkSec, Kit.tokens.paper, 0.45)
                }
                TacitText {
                    visible: cell.row === 7
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: Kit.tokens.space.xs
                    }
                    text: Fen.files[board.flipped ? 7 - cell.col : cell.col]
                    size: "meta"
                    color: cell.light ? Kit.tokens.paperInkSec
                        : Mix.mix(Kit.tokens.paperInkSec, Kit.tokens.paper, 0.45)
                }
            }
        }
    }

    Repeater {
        model: board.fades
        delegate: Item {
            id: leaving
            required property var modelData
            width: board.cell
            height: board.cell
            x: modelData.x
            y: modelData.y
            z: 5

            Image {
                anchors.fill: parent
                source: board.pieceSource(leaving.modelData.piece)
                sourceSize: Qt.size(board.cell, board.cell)
                fillMode: Image.PreserveAspectFit
            }
            SequentialAnimation {
                running: true
                PauseAnimation { duration: Math.round(board.glideMs * 0.55) }
                NumberAnimation {
                    target: leaving
                    property: "opacity"
                    to: 0
                    duration: Math.round(board.glideMs * 0.45)
                    easing.type: Easing.InQuad
                }
            }
        }
    }

    Repeater {
        model: board.movers
        delegate: Item {
            id: gliding
            required property var modelData
            width: board.cell
            height: board.cell
            x: modelData.fromX
            y: modelData.fromY
            z: 6

            Image {
                anchors.fill: parent
                source: board.pieceSource(gliding.modelData.piece)
                sourceSize: Qt.size(board.cell, board.cell)
                fillMode: Image.PreserveAspectFit
            }
            ParallelAnimation {
                running: true
                NumberAnimation {
                    target: gliding
                    property: "x"
                    to: gliding.modelData.toX
                    duration: board.glideMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: gliding
                    property: "y"
                    to: gliding.modelData.toY
                    duration: board.glideMs
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Accessible.role: Accessible.Grouping
    Accessible.name: "Chess board"
}
