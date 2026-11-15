// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: engine

    readonly property string executable: Quickshell.env("CHESS_STOCKFISH")
        || (Quickshell.env("PWD") || ".") + "/engine/stockfish"
    property bool available: false
    property bool ready: false
    property bool thinking: false
    property bool ignoreNextBestMove: false
    property string status: "Preparing game"

    signal moveReady(string from, string to, string promotion)

    function start() {
        if (!process.running)
            process.running = true;
    }

    function newGame() {
        if (!engine.ready)
            return;
        process.write("ucinewgame\nisready\n");
        engine.status = "Your move";
    }

    function requestMove(fen) {
        if (!engine.ready || engine.thinking)
            return;
        engine.thinking = true;
        engine.status = "Computer is thinking";
        process.write("position fen " + fen + "\ngo movetime 700\n");
    }

    function cancelSearch() {
        if (!engine.thinking)
            return;
        engine.ignoreNextBestMove = true;
        engine.thinking = false;
        process.write("stop\n");
    }

    function fail(message) {
        engine.available = false;
        engine.ready = false;
        engine.thinking = false;
        engine.status = "Computer unavailable";
        console.warn("Chess engine:", message);
    }

    function handleLine(line) {
        const text = line.trim();
        if (text === "uciok")
            process.write("setoption name Threads value 1\nsetoption name Hash value 32\nisready\n");
        else if (text === "readyok") {
            engine.available = true;
            engine.ready = true;
            if (!engine.thinking)
                engine.status = "Your move";
        } else if (text.startsWith("bestmove ")) {
            if (engine.ignoreNextBestMove) {
                engine.ignoreNextBestMove = false;
                return;
            }
            engine.thinking = false;
            const match = /^bestmove ([a-h][1-8])([a-h][1-8])([qrbn])?/.exec(text);
            if (match)
                engine.moveReady(match[1], match[2], match[3] || "q");
        }
    }

    Process {
        id: process
        command: [engine.executable]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => engine.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("Stockfish:", data)
        }
        onStarted: {
            process.write("uci\n");
        }
        onExited: (exitCode, exitStatus) => {
            if (engine.available || !engine.ready)
                engine.fail("process exited with code " + exitCode);
        }
    }
}