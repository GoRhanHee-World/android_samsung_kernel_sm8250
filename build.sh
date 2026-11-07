#!/usr/bin/env bash
set -e

SECONDS=0 # builtin bash timer

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== AnyKernel3 =====
AK3_REPO="https://github.com/notkernel-oss/AnyKernel3"
AK3_BRANCH="$DEVICE"

BUILD_MODE="${BUILD_MODE:-ksu}"
case "$BUILD_MODE" in
    ksu|stock)
        MODE_CONFIG="vendor/not/${BUILD_MODE}.config"
        ;;
    *)
        echo "Invalid BUILD_MODE '$BUILD_MODE'; expected ksu or stock." >&2
        exit 1
        ;;
esac

ZIPNAME="not-${BUILD_MODE}-$(date '+%Y%m%d').zip"
TC_DIR="$(pwd)/tc/clang"
DEFCONFIG="vendor/kona-perf_defconfig vendor/samsung/kona-sec-common.config vendor/samsung/$DEVICE.config $MODE_CONFIG vendor/not/localversion.config"

OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
DTS_DIR="$BOOT_DIR/dts/vendor/qcom"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8)-$DEVICE.zip"
fi

git submodule update --init --recursive

export PATH="$TC_DIR/bin:$PATH"

if ! [ -d "$TC_DIR" ]; then
    echo -e "${YELLOW}Clang not found! Downloading...${NC}"
    mkdir -p "$TC_DIR"

    ASSET_URL=$(
        curl -fsSL https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest |
        jq -r '.assets[]
            | select(.name | endswith(".tar.zst"))
            | .browser_download_url' |
        head -n1
    )

    if [ -z "$ASSET_URL" ]; then
        echo -e "${RED}Failed to find latest release!${NC}"
        exit 1
    fi

    if ! curl -L "$ASSET_URL" | tar --zstd -x -C "$TC_DIR" --strip-components=1; then
        echo -e "${RED}Download failed!${NC}"
        exit 1
    fi

    echo -e "${GREEN}Clang ready!${NC}"
fi

mkdir -p out
echo -e "${YELLOW}building with: $DEFCONFIG${NC}"

make O=out ARCH=arm64 $DEFCONFIG
make O=out ARCH=arm64 olddefconfig

if [ "$BUILD_MODE" = ksu ]; then
    if ! grep -qx 'CONFIG_KSU=y' out/.config; then
        echo "KernelSU was not enabled in the generated configuration." >&2
        exit 1
    fi
elif grep -Eq '^CONFIG_KSU=[ym]$' out/.config; then
    echo "KernelSU is still enabled in the stock configuration." >&2
    exit 1
fi

echo -e "\n${YELLOW}Starting compilation...${NC}\n"

make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 dtbo.img
    
make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 Image

# Samsung's three base DTBs, in the same order as the previous sorted list.
DTBS=("$DTS_DIR/kona-v2.1.dtb" "$DTS_DIR/kona-v2.dtb" "$DTS_DIR/kona.dtb")
for file in "$BOOT_DIR/Image" "$BOOT_DIR/dtbo.img" "${DTBS[@]}"; do
    if [ ! -s "$file" ]; then
        echo "Missing or empty build output: $file" >&2
        exit 1
    fi
done
cat "${DTBS[@]}" > "$BOOT_DIR/dtb"

rm -rf AnyKernel3
echo "[*] Cloning AnyKernel3 for $DEVICE"
git clone -q -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

echo -e "Preparing zip...\n"

cp "$BOOT_DIR/dtbo.img" AnyKernel3/dtbo.img
cp "$BOOT_DIR/Image" AnyKernel3/Image
cp "$BOOT_DIR/dtb" AnyKernel3/dtb

# Match the upstream installer to the payloads produced by this build.
# shellcheck disable=SC2016
sed -i \
    -e 's/^supported\.versions=13 - 16$/supported.versions=13 - 17/' \
    -e 's/android\.is_ous/android.is_uos/g' \
    -e '/^case "\$ZIPFILE" in$/,/^esac$/c\
# Use the DTB built with this kernel, independently of the ZIP filename.\
[ -s "$home/dtb" ] || abort "Missing or empty dtb. Aborting...";' \
    AnyKernel3/anykernel.sh
if grep -Eq 'kona(-eff)?\.dtb|android\.is_ous|^supported\.versions=13 - 16$' AnyKernel3/anykernel.sh; then
    echo "AnyKernel3 installer still contains incompatible settings." >&2
    exit 1
fi
sh -n AnyKernel3/anykernel.sh

cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md '*placeholder'
cd ..

echo -e "\n${GREEN}Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!${NC}"
echo -e "${GREEN}Zip: $ZIPNAME${NC}"
