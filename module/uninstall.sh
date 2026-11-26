#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
restore_all
rm -rf /data/adb/bluedmc-tuning
