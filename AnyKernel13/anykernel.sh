# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
# Adapted for Samsung Galaxy A20 (SM-A205F)

## AnyKernel setup
properties() { '
kernel.string=Eureka Kernel + KernelSU-Next by YOUR_NAME
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=a20
device.name2=A20
device.name3=SM-A205F
device.name4=SM-A205FN
device.name5=SM-A205G
'; }

## AnyKernel methods (DO NOT CHANGE)
# import patching functions/variables - see ./tools/ak3-core.sh
. tools/ak3-core.sh;

## Samsung-specific boot image setup
# A20 uses Samsung's proprietary boot image format; we flash the kernel
# directly into the boot partition using Samsung's naming convention.

## Dump/patch/restore boot image
dump_boot;

## Flash the kernel image
# For Samsung Exynos devices the kernel image slot is 'kernel'
write_boot;

## Optionally flash DTB
if [ -f "$ZIPFILE_DIR/dtb.img" ]; then
    flash_dtb dtb.img;
fi

## End

ui_print " ";
ui_print "========================================";
ui_print "  Samsung Galaxy A20 (SM-A205F)";
ui_print "  Eureka Kernel + KernelSU-Next";
ui_print "========================================";
ui_print " ";
ui_print "  Flash complete!";
ui_print "  Reboot and open KernelSU-Next manager";
ui_print "  to verify root status.";
ui_print " ";
