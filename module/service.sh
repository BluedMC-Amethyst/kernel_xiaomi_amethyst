#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
# wait for boot, then let vendor post_boot scripts and HyperOS perf services settle first
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 30
: > "$LOG"
apply >/dev/null
