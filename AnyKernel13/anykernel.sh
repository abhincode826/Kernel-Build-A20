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

BLOCK=/dev/block/platform/13500000.dwmmc0/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;
split_boot;
ui_print "- Installing Eureka Kernel + KernelSU-Next";
flash_boot;
ui_print "- Done!";
