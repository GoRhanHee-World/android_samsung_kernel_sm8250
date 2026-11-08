#!/usr/bin/env bash
set -euo pipefail

TC_DIR="${1:?Usage: download_clang.sh TOOLCHAIN_DIR}"
# Pin the release so builds do not depend on GitHub's latest-release API.
CLANG_RELEASE=06092026
CLANG_SHA256=531083928c8e37f6b31e324dbfd0b5a8323f989b1c57ff2c1368b889b5b1bd30
ASSET_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/$CLANG_RELEASE/neutron-clang-$CLANG_RELEASE.tar.zst"

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

echo "Downloading Neutron Clang $CLANG_RELEASE directly..."
if ! curl "${CURL_OPTIONS[@]}" --max-time 1800 \
    --output "$TC_STAGE/clang.tar.zst" "$ASSET_URL"; then
    echo "Failed to download Clang after retries." >&2
    exit 1
fi

printf '%s  %s\n' "$CLANG_SHA256" "$TC_STAGE/clang.tar.zst" | sha256sum --check
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
