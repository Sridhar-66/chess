#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
app_dir="$data_home/tacit/apps/chess"
applications_dir="$data_home/applications"

# A normal install copies the sources. --link keeps the installed app pointing at this
# checkout instead, so edits show on the next launch without running the installer again.
link=false
case "${1:-}" in
    --link) link=true ;;
    "") ;;
    *) printf 'usage: %s [--link]\n' "$0" >&2; exit 2 ;;
esac

"$repo/tools/install-stockfish.sh"

mkdir -p "$app_dir/bin" "$app_dir/engine" "$applications_dir"

# Replace the app's sources, so files removed from the checkout leave the install too.
rm -rf "$app_dir/board" "$app_dir/lib" "$app_dir/pages"
rm -f "$app_dir"/*.qml "$app_dir/qmldir" "$app_dir/LICENSE"
if $link; then
    ln -s "$repo"/*.qml "$app_dir/"
    ln -s "$repo/qmldir" "$repo/LICENSE" "$app_dir/"
    ln -s "$repo/board" "$repo/lib" "$repo/pages" "$app_dir/"
else
    cp "$repo"/*.qml "$repo/qmldir" "$repo/LICENSE" "$app_dir/"
    cp -R "$repo/board" "$repo/lib" "$repo/pages" "$app_dir/"
fi

# Copy a file only when it changed; the engine binary is large.
copy_if_changed() {
    src=$1
    dst=$2
    mode=$3
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
        install -m "$mode" "$src" "$dst"
    fi
}
install_launcher() {
    src=$1
    dst=$2
    mode=$3
    if $link; then
        rm -f "$dst"
        ln -s "$src" "$dst"
    else
        copy_if_changed "$src" "$dst" "$mode"
    fi
}

copy_if_changed "$repo/engine/stockfish" "$app_dir/engine/stockfish" 755
copy_if_changed "$repo/engine/Copying.txt" "$app_dir/engine/Copying.txt" 644
copy_if_changed "$repo/engine/version" "$app_dir/engine/version" 644
install_launcher "$repo/assets/chess-rook.svg" "$app_dir/icon.svg" 644
install_launcher "$repo/packaging/chess-run" "$app_dir/bin/chess" 755

printf '[Desktop Entry]\nType=Application\nName=Chess\nComment=Play chess against the computer\nIcon=%s\nExec="%s"\nTerminal=false\nCategories=Game;BoardGame;\n' \
    "$app_dir/icon.svg" "$app_dir/bin/chess" > "$applications_dir/tacit-chess.desktop"

printf 'Installed Chess for Tacit at %s\nLauncher: %s\n' "$app_dir" "$applications_dir/tacit-chess.desktop"
