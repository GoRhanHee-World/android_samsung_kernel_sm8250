#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 OUTPUT_ZIP BOOT_DIR DEVICE [Image|Image.gz]" >&2
    exit 2
fi

PREBUILTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$PREBUILTS_DIR/AnyKernel3"
OUTPUT_ZIP="$1"
BOOT_DIR="$2"
DEVICE="$3"
IMAGE="${4:-Image}"

case "$DEVICE" in
    bloomxq|c1q|c2q|f2q|gts7l|gts7lwifi|gts7xl|gts7xlwifi|r8q|x1q|y2q|z3q) ;;
    *) echo "Unsupported SM8250 device: $DEVICE" >&2; exit 1 ;;
esac
case "$IMAGE" in
    Image|Image.gz) ;;
    *) echo "Unsupported kernel image: $IMAGE" >&2; exit 1 ;;
esac

for file in "$BOOT_DIR/$IMAGE" "$BOOT_DIR/dtb" "$BOOT_DIR/dtbo.img" \
    "$TEMPLATE_DIR/LICENSE" "$TEMPLATE_DIR/tools/ak3-core.sh" \
    "$TEMPLATE_DIR/META-INF/com/google/android/update-binary"; do
    if [[ ! -s "$file" ]]; then
        echo "Missing or empty package input: $file" >&2
        echo "Initialize prebuilts/AnyKernel3 with git submodule update --init --recursive." >&2
        exit 1
    fi
done

mkdir -p -- "$(dirname -- "$OUTPUT_ZIP")"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8250-anykernel.XXXXXX")"
trap 'rm -rf -- "$STAGE_DIR"' EXIT

cp -a "$TEMPLATE_DIR/LICENSE" "$TEMPLATE_DIR/META-INF" "$TEMPLATE_DIR/tools" "$STAGE_DIR/"
INSTALLER="$(< "$PREBUILTS_DIR/anykernel.sh")"
printf '%s\n' "${INSTALLER//@DEVICE@/$DEVICE}" > "$STAGE_DIR/anykernel.sh"
sh -n "$STAGE_DIR/anykernel.sh"

for file in "$IMAGE" dtb dtbo.img; do
    cp "$BOOT_DIR/$file" "$STAGE_DIR/$file"
    chmod 0644 "$STAGE_DIR/$file"
done
chmod 0755 "$STAGE_DIR/anykernel.sh" "$STAGE_DIR/META-INF/com/google/android/update-binary"
find "$STAGE_DIR/tools" -type f -exec chmod 0755 {} +

(
    cd "$STAGE_DIR"
    zip -r9 -q flashable.zip LICENSE META-INF tools anykernel.sh "$IMAGE" dtb dtbo.img
)
mv -f -- "$STAGE_DIR/flashable.zip" "$OUTPUT_ZIP"
echo "Created $OUTPUT_ZIP"
