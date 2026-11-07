#!/bin/sh
# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers; SM8250 installer maintained in this repository.

properties() { : '
kernel.string=not_kernel for @DEVICE@
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=@DEVICE@
device.name2=@DEVICE@xx
device.name3=@DEVICE@xxx
supported.versions=13 - 17
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=/dev/block/platform/soc/1d84000.ufshc/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_MAGISK_CHECK=1;

. tools/ak3-core.sh;

for payload in dtb dtbo.img; do
    [ -s "$AKHOME/$payload" ] || abort "Missing or empty $payload. Aborting...";
done;
[ -s "$AKHOME/Image" ] || [ -s "$AKHOME/Image.gz" ] || abort "Missing kernel image. Aborting...";

split_boot;

# The kernel uses android.is_aosp to select touchscreen/fingerprint behavior.
oneui=$(file_getprop /system/build.prop ro.build.version.oneui);
if [ -n "$oneui" ]; then
    patch_cmdline "android.is_aosp" "android.is_aosp=0";
else
    patch_cmdline "android.is_aosp" "android.is_aosp=1";
fi;
if [ "$oneui" = "80000" ]; then
    patch_cmdline "android.is_uos" "android.is_uos=1";
else
    patch_cmdline "android.is_uos" "android.is_uos=0";
fi;

flash_boot;
flash_generic dtbo;
