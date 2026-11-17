#!/usr/bin/env bash
# Adapt MinsOS build_kernel_local.sh: KOR wins colliding board IDs, then JPN,
# then CHN. Output <board-id> <compiled-overlay-path> without building anything.
set -euo pipefail
[ "$#" = 3 ] || { echo "Usage: $0 <device> <source-root> <compiled-dts-dir>" >&2; exit 1; }
device=$1
source_root=$2
compiled=$3
case "$device" in x1q|y2q|z3q) ;; *) echo "Unsupported device: $device" >&2; exit 1 ;; esac
declare -A seen=()
for region in kor jpn chn; do
    found=0
    for file in "$compiled/kona-sec-$device-$region-"*.dtbo; do
        [ -s "$file" ] || continue
        found=1
        source_file="$source_root/arch/arm64/boot/dts/samsung/$device/$(basename "${file%.dtbo}").dts"
        board=$(sed -nE 's/.*qcom,board-id[[:space:]]*=[[:space:]]*<[0-9]+[[:space:]]+([0-9]+)>.*/\1/p' "$source_file")
        [[ "$board" =~ ^[0-9]+$ ]] || { echo "Missing or ambiguous board ID: $source_file" >&2; exit 1; }
        [ -z "${seen[$board]:-}" ] || continue
        seen[$board]=1
        printf '%s %s\n' "$board" "$file"
    done
    [ "$found" = 1 ] || { echo "No $region overlays for $device" >&2; exit 1; }
done
if [ -z "${seen[13]:-}" ] || [ -z "${seen[14]:-}" ]; then
    echo "Missing Korean board IDs" >&2
    exit 1
fi
if [ "$device" = y2q ] && [ -z "${seen[15]:-}" ]; then
    echo "Missing Japanese S20+ board ID 15" >&2
    exit 1
fi
