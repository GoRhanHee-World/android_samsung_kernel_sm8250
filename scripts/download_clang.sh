#!/usr/bin/env bash
set -euo pipefail

TC_DIR="${1:?Usage: download_clang.sh TOOLCHAIN_DIR}"

if [ -x "$TC_DIR/bin/clang" ] && "$TC_DIR/bin/clang" --version >/dev/null 2>&1; then
    echo "Using Clang from $TC_DIR"
    exit 0
fi

mkdir -p "$(dirname -- "$TC_DIR")"
TC_STAGE=$(mktemp -d "$(dirname -- "$TC_DIR")/.clang-download.XXXXXX")
trap 'rm -rf -- "$TC_STAGE"' EXIT

CURL_OPTIONS=(
    --fail --location --silent --show-error
    --retry 5 --retry-all-errors --retry-delay 5
    --connect-timeout 20
)

echo "Fetching the latest Neutron Clang release..."
if ! curl "${CURL_OPTIONS[@]}" --max-time 120 \
    --output "$TC_STAGE/release.json" \
    https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest; then
    echo "Failed to fetch Clang release information after retries." >&2
    exit 1
fi

if ! ASSET_URL=$(jq -er \
    '[.assets[] | select(.name | endswith(".tar.zst")) | .browser_download_url][0] // empty' \
    "$TC_STAGE/release.json"); then
    echo "Clang release response has no .tar.zst download URL." >&2
    exit 1
fi

echo "Downloading Clang..."
if ! curl "${CURL_OPTIONS[@]}" --max-time 1800 \
    --output "$TC_STAGE/clang.tar.zst" "$ASSET_URL"; then
    echo "Failed to download Clang after retries." >&2
    exit 1
fi

mkdir "$TC_STAGE/extracted"
tar --zstd -xf "$TC_STAGE/clang.tar.zst" -C "$TC_STAGE/extracted" --strip-components=1
if [ ! -x "$TC_STAGE/extracted/bin/clang" ] || \
    ! "$TC_STAGE/extracted/bin/clang" --version; then
    echo "Downloaded toolchain does not contain a working Clang executable." >&2
    exit 1
fi

# Replace an incomplete previous installation only after validating the download.
rm -rf -- "$TC_DIR"
mv -- "$TC_STAGE/extracted" "$TC_DIR"
echo "Clang ready: $TC_DIR"
