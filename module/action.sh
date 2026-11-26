#!/system/bin/sh
# KernelSU-Next / Magisk action button: cycle stock -> balanced -> performance -> battery
MODDIR=${0%/*}
. "$MODDIR/common.sh"
cur=$(cat "$D/profile" 2>/dev/null); cur=${cur:-balanced}
case $cur in
  stock) next=balanced;; balanced) next=performance;; performance) next=battery;; *) next=stock;;
esac
echo "$next" > "$D/profile"
echo "BluedMC Tuning: $cur -> $next"
apply >/dev/null
echo "Applied. Log: $LOG"
grep -E 'set |restored |FAILED' "$LOG" | tail -12
