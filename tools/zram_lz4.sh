#!/system/bin/sh
# BluedMC: make zram use lz4 (NEON-accelerated in BluedMC v1.2+).
# Runs at post-fs-data, before HyperOS's system_perf_init sizes zram (12 GB + flash writeback),
# so Xiaomi's normal zram setup is kept and only the compressor changes.
i=0
while [ ! -e /sys/block/zram0/comp_algorithm ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ "$(cat /sys/block/zram0/disksize 2>/dev/null)" = "0" ] && echo lz4 > /sys/block/zram0/comp_algorithm
exit 0
