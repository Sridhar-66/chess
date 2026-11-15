#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=sf_19

case $(uname -m) in
    x86_64|amd64)
        asset=stockfish-linux-x86-64-universal.tar.gz
        digest=9defc0d4e55d49c65a6d042f3e571a39fcea499ade6dbe741b53b8c65e03611f
        executable=stockfish-linux-x86-64-universal
        ;;
    aarch64|arm64)
        asset=stockfish-linux-arm64-universal.tar.gz
        digest=fe26cfd1d9db4c8af3d21e24d9ff34cacb31c1f940085a7583da11796f2bac01
        executable=stockfish-linux-arm64-universal
        ;;
    riscv64)
        asset=stockfish-linux-riscv64-universal.tar.gz
        digest=d4b4d118c003bc669a939d9fb208e3ef6b367730fd79a70dbc278b18475df3d1
        executable=stockfish-linux-riscv64-universal
        ;;
    *)
        printf 'Unsupported Stockfish architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

for tool in curl tar sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required tool is missing: %s\n' "$tool" >&2
        exit 1
    fi
done

if [ -x "$repo/engine/stockfish" ] && [ -f "$repo/engine/version" ]; then
    installed_version=
    IFS= read -r installed_version < "$repo/engine/version"
fi
if [ "${installed_version:-}" = "$version" ]; then
    printf 'Stockfish sf_19 is already installed at %s\n' "$repo/engine/stockfish"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
url="https://github.com/official-stockfish/Stockfish/releases/download/$version/$asset"
curl --fail --location --retry 3 "$url" --output "$tmp/stockfish.tar.gz"
printf '%s  %s\n' "$digest" "$tmp/stockfish.tar.gz" | sha256sum --check --status
tar -xzf "$tmp/stockfish.tar.gz" -C "$tmp" "stockfish/$executable" "stockfish/Copying.txt"

mkdir -p "$repo/engine"
install -m 755 "$tmp/stockfish/$executable" "$repo/engine/stockfish"
install -m 644 "$tmp/stockfish/Copying.txt" "$repo/engine/Copying.txt"
printf '%s\n' "$version" > "$repo/engine/version"
printf 'Installed Stockfish %s for %s at %s\n' "$version" "$(uname -m)" "$repo/engine/stockfish"