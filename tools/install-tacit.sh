#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
app_dir="$data_home/tacit/apps/chess"
applications_dir="$data_home/applications"

"$repo/tools/install-stockfish.sh"

mkdir -p "$app_dir/bin" "$app_dir/engine" "$applications_dir"

# Replace the app's sources, so files removed from the checkout leave the install too.
rm -rf "$app_dir/board" "$app_dir/lib" "$app_dir/pages"
rm -f "$app_dir"/*.qml
cp "$repo"/*.qml "$repo/qmldir" "$repo/LICENSE" "$app_dir/"
cp -R "$repo/board" "$repo/lib" "$repo/pages" "$app_dir/"

# Copy a file only when it changed; the engine binary is large.
copy_if_changed() {
    src=$1
    dst=$2
    mode=$3
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
        install -m "$mode" "$src" "$dst"
    fi
}

copy_if_changed "$repo/engine/stockfish" "$app_dir/engine/stockfish" 755
copy_if_changed "$repo/engine/Copying.txt" "$app_dir/engine/Copying.txt" 644
copy_if_changed "$repo/engine/version" "$app_dir/engine/version" 644
copy_if_changed "$repo/assets/chess-rook.svg" "$app_dir/icon.svg" 644
copy_if_changed "$repo/packaging/chess-run" "$app_dir/bin/chess" 755

printf '[Desktop Entry]\nType=Application\nName=Chess\nComment=Play chess against the computer\nIcon=%s\nExec="%s"\nTerminal=false\nCategories=Game;BoardGame;\n' \
    "$app_dir/icon.svg" "$app_dir/bin/chess" > "$applications_dir/tacit-chess.desktop"

printf 'Installed Chess for Tacit at %s\nLauncher: %s\n' "$app_dir" "$applications_dir/tacit-chess.desktop"
