// SPDX-License-Identifier: GPL-3.0-or-later
// Reading a FEN string (the one line that describes a position): which piece stands on which square.
// .rows("rnbq... w KQkq - 0 1") gives eight strings of eight characters, rank 8 first, "." where the
// square is empty. squareOf(index) names the square at an index.
.pragma library

function rows(fen) {
    const out = [];
    for (const rank of (fen.split(" ")[0] || "").split("/"))
        out.push(expand(rank));
    while (out.length < 8)
        out.push("........");
    return out.slice(0, 8);
}

// "5k2" into ".....k.."
function expand(rank) {
    let out = "";
    for (const c of rank) {
        if (c >= "1" && c <= "8")
            out += ".".repeat(Number(c));
        else
            out += c;
    }
    while (out.length < 8)
        out += ".";
    return out.slice(0, 8);
}

// the files, left to right on White's side
const files = ["a", "b", "c", "d", "e", "f", "g", "h"];

// "e4" is file 4, rank 4: the array index from the bottom left
function indexAt(square) {
    return (8 - Number(square[1])) * 8 + files.indexOf(square[0]);
}

function squareOf(index) {
    return files[index % 8] + String(8 - Math.floor(index / 8));
}
