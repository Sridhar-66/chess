// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import Quickshell
import "lib/chess.js" as ChessLib

// The game: its rules are chess.js's (BSD-2-Clause, bundled in lib/), which knows castling, en passant,
// promotion with a choice of piece, check, checkmate, stalemate, the draws by repetition and the
// fifty-move rule and by insufficient material. Everything here is the record and the verdict; what the
// board shows and what the engine says are other files' business.
Singleton {
    id: game

    readonly property var rules: new ChessLib.Chess()
    property int revision: 0

    // what the position is
    readonly property string fen: {
        game.revision;
        return rules.fen();
    }
    // "w" or "b": who is to move
    readonly property string turn: {
        game.revision;
        return rules.turn();
    }
    // the side to move is in check
    readonly property bool check: {
        game.revision;
        return rules.in_check();
    }

    // the move just played, in chess words; empty before the first move and after an undo past the start
    property string lastFrom: ""
    property string lastTo: ""

    // the game so far, chess.js's verbose history: {color, from, to, piece, san, flags, ...}
    readonly property var history: {
        game.revision;
        return rules.history({ verbose: true });
    }

    // how a game ended while it was still playable: "checkmate" | "stalemate" | "repetition" |
    // "fifty" | "material". Empty while it goes on.
    property string endReason: ""
    // who won: "w" or "b", empty for a draw and while the game goes on
    property string winner: ""
    readonly property bool over: endReason !== ""
    readonly property string resultText: {
        if (endReason === "checkmate")
            return "Checkmate: " + (winner === "w" ? "White wins" : "Black wins");
        if (endReason === "stalemate")
            return "Stalemate: draw";
        if (endReason === "repetition")
            return "Draw by repetition";
        if (endReason === "fifty")
            return "Draw by the 50-move rule";
        if (endReason === "material")
            return "Draw: insufficient material";
        return "";
    }

    // every change to the position
    signal moved()
    signal eventOccurred(string message, string kind)
    onMoved: game.revision++

    // legal moves from one square, chess.js's verbose moves ({from, to, piece, flags, promotion?}).
    // A promotion to the last rank comes back as four moves, one for each piece.
    function legalMoves(square) {
        if (game.over || square.length !== 2)
            return [];
        return rules.moves({ square: square, verbose: true });
    }

    // the piece on a square: {type: "p".."k", color: "w"|"b"} or null
    function pieceAt(square) {
        return rules.get(square);
    }

    // true when the piece on `square` may be picked up now: there is one, it is the side to move's,
    // and the game is not over
    function canPick(square) {
        if (game.over)
            return false;
        const p = rules.get(square);
        return !!p && p.color === game.turn;
    }

    // play a move. `promotion` is the piece to promote to when the move is a promotion ("q","r","b","n").
    // Returns the played move (chess.js's verbose one) or null when the move is not legal.
    function makeMove(from, to, promotion) {
        if (game.over)
            return null;
        const m = rules.move({ from: from, to: to, promotion: promotion ?? "q" });
        if (!m)
            return null;
        game.lastFrom = m.from;
        game.lastTo = m.to;
        game.evaluateEnd();
        game.moved();
        const events = game.eventLog();
        const latest = events[events.length - 1];
        if (latest)
            game.eventOccurred(latest.text, latest.kind);
        return m;
    }

    // take back the last move. The game is on again afterwards, even if it had ended.
    function undo() {
        if (!rules.undo())
            return false;
        game.rememberLast();
        game.endReason = "";
        game.winner = "";
        game.moved();
        return true;
    }

    function undoToWhite() {
        if (!game.undo())
            return false;
        if (game.turn === "b")
            game.undo();
        return true;
    }

    // a fresh game
    function newGame() {
        rules.reset();
        game.lastFrom = "";
        game.lastTo = "";
        game.endReason = "";
        game.winner = "";
        game.moved();
    }

    // the verdict of the position itself: mate, stalemate and the three draws chess.js knows
    function evaluateEnd() {
        if (rules.in_checkmate()) {
            game.endReason = "checkmate";
            game.winner = rules.turn() === "w" ? "b" : "w";
        } else if (rules.in_stalemate()) {
            game.endReason = "stalemate";
            game.winner = "";
        } else if (rules.insufficient_material()) {
            game.endReason = "material";
            game.winner = "";
        } else if (rules.in_threefold_repetition()) {
            game.endReason = "repetition";
            game.winner = "";
        } else if (Number(rules.fen().split(" ")[4] ?? 0) >= 100) {
            // the halfmove clock, the FEN's fifth field: fifty moves without a pawn move or a capture
            game.endReason = "fifty";
            game.winner = "";
        } else {
            game.endReason = "";
            game.winner = "";
        }
    }

    // the last move from the history (an undo can step past the start)
    function rememberLast() {
        const h = rules.history({ verbose: true });
        game.lastFrom = h.length > 0 ? h[h.length - 1].from : "";
        game.lastTo = h.length > 0 ? h[h.length - 1].to : "";
    }

    function eventLog() {
        const moves = rules.history({ verbose: true });
        const events = [];
        for (const move of moves) {
            const side = move.color === "w" ? "White" : "Black";
            const opponent = move.color === "w" ? "Black" : "White";
            const castleSide = move.flags.indexOf("k") >= 0 ? "king-side"
                : move.flags.indexOf("q") >= 0 ? "queen-side" : "";
            if (castleSide !== "") {
                const notation = castleSide === "king-side" ? "O-O" : "O-O-O";
                events.push({ text: side + " castled " + castleSide + " (" + notation + ")", kind: "castle" });
            } else if (move.san.endsWith("#")) {
                events.push({ text: side + " checkmated " + opponent, kind: "checkmate" });
            } else if (move.san.endsWith("+")) {
                events.push({ text: side + " checked " + opponent, kind: "check" });
            } else {
                events.push({ text: side + ": " + move.san, kind: "move" });
            }
            if (castleSide !== "" && move.san.endsWith("+"))
                events.push({ text: side + " checked " + opponent, kind: "check" });
        }

        if (game.endReason === "stalemate")
            events.push({ text: game.resultText, kind: "stalemate" });
        else if (game.over && game.endReason !== "checkmate")
            events.push({ text: game.resultText, kind: "terminal" });
        if (events.length === 0)
            events.push({ text: "Game started", kind: "start" });
        return events;
    }
}
