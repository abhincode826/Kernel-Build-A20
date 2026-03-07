# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
# Adapted for Samsung Galaxy A20 (SM-A205F)

properties() { '
kernel.string=Eureka Kernel + KernelSU-Next by Abhin
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

if [ -e /dev/block/platform/13500000.dwmmc0/by-name/BOOT ]; then
    block=/dev/block/platform/13500000.dwmmc0/by-name/BOOT;
elif [ -e /dev/block/platform/13500000.dwmmc0/by-name/boot ]; then
    block=/dev/block/platform/13500000.dwmmc0/by-name/boot;
fi
is_slot_device=0;
ramdisk_compression=auto;

. tools/ak3-core.sh;

split_boot;
ui_print "- Installing Eureka Kernel + KernelSU-Next";
flash_boot;
ui_print " ";
ui_print "- Installing DTB";
flash_dtb;
ui_print " ";
ui_print "========================================";
ui_print "  Samsung Galaxy A20 (SM-A205F)";
ui_print "  Eureka Kernel + KernelSU-Next";
ui_print "  Flash complete! Reboot to verify.";
ui_print "========================================";
