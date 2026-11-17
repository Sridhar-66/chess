# Chess for Tacit

A Quickshell chess app built with Tacit.Kit. Play as White against the bundled Stockfish engine; chess.js handles
legal moves, promotion, check, and game-end rules.

The pieces live in `board/pieces/`: Colin M.L. Burnett's set (the Lichess default) with a custom bishop and rounded
corners. Its BSD-3-Clause licence is in `board/pieces/LICENCE-cburnett.txt`.

## Install for this Tacit user

From a checkout on a supported Linux device, run:

```sh
./tools/install-tacit.sh
```

The installer downloads and verifies the official Stockfish sf_19 universal binary for the device architecture,
installs the app under `~/.local/share/tacit/apps/chess`, and registers a `Chess` desktop launcher under
`~/.local/share/applications`. It does not replace or reconfigure Tacit's shell. Quickshell and Tacit.Kit must
already be installed.

While developing, run it with `--link`. The installed launcher then reads the QML, board, and page files straight
from this checkout, so edits show the next time the app starts; reopen the app after changing a file:

```sh
./tools/install-tacit.sh --link
```

To run directly from the checkout after installing Stockfish:

```sh
./tools/install-stockfish.sh
qs -p chess.qml
```

Set `CHESS_STOCKFISH` to an executable UCI-compatible Stockfish binary to use a separately managed engine.
Stockfish is GPL-3.0; its license is installed alongside the binary.