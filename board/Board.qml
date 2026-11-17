// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Tacit.Kit
import ".."
import "../lib/Fen.js" as Fen
import "../lib/Color.js" as Mix

// The board and everything done on it: eight by eight squares from a FEN string, the pieces on them,
// picking a piece up by click or drag or by keyboard (the board is one Tab stop; the arrows move a cursor
// square, Enter or Space picks a piece up or sets it down, Escape takes the pick back), the dots on its
// legal moves (a ring where a capture lands), the last move and a king in check marked, files and ranks in
// the corners of the edge squares. It reads
// its colours from the palette (the light square is the document's paper, the dark one the document's
// quieter ink walked a little way back towards it), so it sits well on every wallpaper. Flipped, rank 1
// and file h come to the bottom left.
Item {
    id: board

    property real side: 480
    property bool flipped: false
    // the room outside the playing squares for the files and ranks
    property int gutter: Kit.tokens.space.l
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

    activeFocusOnTab: true
    Keys.onLeftPressed: event => { moveCursor(0, -1); event.accepted = true }
    Keys.onRightPressed: event => { moveCursor(0, 1); event.accepted = true }
    Keys.onUpPressed: event => { moveCursor(-1, 0); event.accepted = true }
    Keys.onDownPressed: event => { moveCursor(1, 0); event.accepted = true }
    Keys.onReturnPressed: event => { cursorPress(); event.accepted = true }
    Keys.onEnterPressed: event => { cursorPress(); event.accepted = true }
    Keys.onSpacePressed: event => { cursorPress(); event.accepted = true }
    Keys.onEscapePressed: deselect()
    onActiveFocusChanged: {
        if (activeFocus)
            wakeCursor();
        else
            deselect();
    }

    // piece art from the cburnett set (the Lichess default), in pieces/. Its drawings name black,
    // white and the light detail lines, and they are swapped here for the palette's ink and paper, so
    // neither side is pure #000 or #fff and the set sits in the app's colours. Black bodies take the
    // paper's secondary ink, so they are not as heavy as the white pieces' outlines.
    readonly property color pieceInk: Mix.mix(Kit.tokens.paperInk, Kit.tokens.paper, 0.08)
    readonly property color pieceBlackInk: Kit.tokens.paperInkSec
    readonly property color piecePaper: Kit.tokens.paper
    property var pieceTexts: ({})
    property var pieceSources: ({})

    // one view per drawing: a FileView's synchronous read happens once, so each drawing keeps its own
    FileView { id: artWP; path: Qt.resolvedUrl("pieces/wP.svg"); blockLoading: true; printErrors: false }
    FileView { id: artWN; path: Qt.resolvedUrl("pieces/wN.svg"); blockLoading: true; printErrors: false }
    FileView { id: artWB; path: Qt.resolvedUrl("pieces/wB.svg"); blockLoading: true; printErrors: false }
    FileView { id: artWR; path: Qt.resolvedUrl("pieces/wR.svg"); blockLoading: true; printErrors: false }
    FileView { id: artWQ; path: Qt.resolvedUrl("pieces/wQ.svg"); blockLoading: true; printErrors: false }
    FileView { id: artWK; path: Qt.resolvedUrl("pieces/wK.svg"); blockLoading: true; printErrors: false }
    FileView { id: artBP; path: Qt.resolvedUrl("pieces/bP.svg"); blockLoading: true; printErrors: false }
    FileView { id: artBN; path: Qt.resolvedUrl("pieces/bN.svg"); blockLoading: true; printErrors: false }
    FileView { id: artBB; path: Qt.resolvedUrl("pieces/bB.svg"); blockLoading: true; printErrors: false }
    FileView { id: artBR; path: Qt.resolvedUrl("pieces/bR.svg"); blockLoading: true; printErrors: false }
    FileView { id: artBQ; path: Qt.resolvedUrl("pieces/bQ.svg"); blockLoading: true; printErrors: false }
    FileView { id: artBK; path: Qt.resolvedUrl("pieces/bK.svg"); blockLoading: true; printErrors: false }

    function colorHex(c) {
        const byte = v => {
            const s = Math.round(v * 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        };
        return "#" + byte(c.r) + byte(c.g) + byte(c.b);
    }
    function pieceText(key) {
        if (pieceTexts[key] === undefined) {
            const art = {
                "wP": artWP, "wN": artWN, "wB": artWB, "wR": artWR, "wQ": artWQ, "wK": artWK,
                "bP": artBP, "bN": artBN, "bB": artBB, "bR": artBR, "bQ": artBQ, "bK": artBK
            }[key];
            pieceTexts[key] = String(art.text());
        }
        return pieceTexts[key];
    }
    function pieceSource(p) {
        if (p === ".")
            return "";
        const key = (p === p.toUpperCase() ? "w" : "b") + p.toUpperCase();
        const ink = colorHex(key[0] === "b" ? pieceBlackInk : pieceInk), paper = colorHex(piecePaper);
        const cacheKey = key + ink + paper;
        if (pieceSources[cacheKey] !== undefined)
            return pieceSources[cacheKey];
        const svg = pieceText(key)
            .replace(/#000/g, ink)
            .replace(/#ececec/g, paper)
            .replace(/#fff/g, paper);
        const source = "data:image/svg+xml;utf8," + encodeURIComponent(svg);
        pieceSources[cacheKey] = source;
        return source;
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

    // keyboard play: the board is one Tab stop, the arrows move a cursor square, Enter or Space picks a piece
    // up or sets it down, Escape takes the pick back. The cursor wakes on the side to move's king.
    property string cursor: ""
    readonly property bool cursorVisible: activeFocus && cursor !== ""

    function displayPoint(square) {
        const file = Fen.files.indexOf(square[0]);
        const rank = Number(square[1]);
        return { "row": board.flipped ? rank - 1 : 8 - rank, "col": board.flipped ? 7 - file : file };
    }
    function squareAtDisplay(row, col) {
        return Fen.files[board.flipped ? 7 - col : col] + String(board.flipped ? row + 1 : 8 - row);
    }
    function wakeCursor() {
        if (cursor === "")
            cursor = kingSquare(turnSide);
    }
    function moveCursor(dRow, dCol) {
        wakeCursor();
        const at = displayPoint(cursor);
        cursor = squareAtDisplay(Math.max(0, Math.min(7, at.row + dRow)), Math.max(0, Math.min(7, at.col + dCol)));
    }
    function cursorPress() {
        if (cursor === "")
            return;
        if (selected !== "" && isTarget(cursor)) {
            moveChosen(selected, cursor);
            deselect();
            return;
        }
        if (canPickUp(cursor))
            selected === cursor ? deselect() : select(cursor);
        else
            deselect();
    }

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

    // the pointer: the mouse or one finger picks a piece, drags it and drops it on a square
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

    // the playing surface, corners rounded: everything drawn on the squares keeps the shape, so the page's
    // ground shows at the corners
    Item {
        id: playing
        width: board.side
        height: board.side
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: boardMask
        }

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

                    // the keyboard's cursor square, a ring while the board holds the keyboard focus
                    Rectangle {
                        anchors.fill: parent
                        visible: board.cursorVisible && square === board.cursor
                        radius: Kit.tokens.radius.art
                        color: "transparent"
                        border.width: Math.max(2, parent.width * 0.05)
                        border.color: board.marked(cell.squareColor, 0.55)
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
    }

    // the shape the playing surface keeps; drawn nowhere, its layer is the mask
    Rectangle {
        id: boardMask
        width: board.side
        height: board.side
        radius: Kit.tokens.radius.window
        visible: false
        layer.enabled: true
    }

    // the files and ranks outside the playing squares, on the page's ground: the numbers down the left,
    // the letters under the board, both read through the flip
    Repeater {
        model: 8
        TacitText {
            required property int index
            x: -board.gutter
            y: index * board.cell
            width: board.gutter - Kit.tokens.space.xs
            height: board.cell
            text: String(board.flipped ? index + 1 : 8 - index)
            size: "fileText"
            ink: "sec"
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }
    Repeater {
        model: 8
        TacitText {
            required property int index
            x: index * board.cell
            y: board.height
            width: board.cell
            height: board.gutter
            text: Fen.files[board.flipped ? 7 - index : index]
            size: "fileText"
            ink: "sec"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Accessible.role: Accessible.Grouping
    Accessible.name: "Chess board"
}
