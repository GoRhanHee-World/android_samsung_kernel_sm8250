#!/usr/bin/env bash
# Run only after compilation. Pack regional DTBOs and describe the exact payload
# so an overseas ROM cannot accidentally ship an older Korean-only kernel.
set -euo pipefail
[ "$#" = 2 ] || { echo "Usage: $0 <device> <boot-dir>" >&2; exit 1; }
device=$1
boot_dir=$2
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
selection=$(mktemp)
trap 'rm -f "$selection"' EXIT
bash "$source_root/scripts/select_s20_dtbo.sh" "$device" "$source_root" \
    "$boot_dir/dts/samsung/$device" > "$selection"
overlays=()
boards=()
while read -r board file; do
    boards+=("$board")
    overlays+=("$file")
done < "$selection"
"$source_root/tools/mkdtimg" create "$boot_dir/dtbo.img" --page_size=4096 "${overlays[@]}"
[ "$(stat -c %s "$boot_dir/dtbo.img")" -le 10485760 ] \
    || { echo "Regional DTBO exceeds the S20 partition size" >&2; exit 1; }

samsung_nfc=false
case "$device" in
    x1q|y2q)
        grep -qx 'CONFIG_SEC_NFC=y' "$source_root/out/.config"
        grep -aFq 'Samsung NFC unit (sales code), leaving the bus to sec-nfc' "$boot_dir/Image"
        grep -aFq 'sec-nfc: NXP NFC unit, leaving the bus to pn547' "$boot_dir/Image"
        samsung_nfc=true
        ;;
esac
board_json=$(printf '%s\n' "${boards[@]}" | jq -s '.')
image_sha=$(sha256sum "$boot_dir/Image" | cut -d ' ' -f 1)
dtb_sha=$(sha256sum "$boot_dir/dtb" | cut -d ' ' -f 1)
dtbo_sha=$(sha256sum "$boot_dir/dtbo.img" | cut -d ' ' -f 1)
jq -n --arg device "$device" --arg source_commit "$(git -C "$source_root" rev-parse HEAD)" \
    --argjson boards "$board_json" --argjson samsung_nfc "$samsung_nfc" \
    --arg image "$image_sha" --arg dtb "$dtb_sha" --arg dtbo "$dtbo_sha" \
    '{schema: 1, device: $device, source_commit: $source_commit,
      board_ids: $boards, samsung_nfc: $samsung_nfc,
      sha256: {Image: $image, dtb: $dtb, "dtbo.img": $dtbo}}' > "$boot_dir/s20-overseas.json"
