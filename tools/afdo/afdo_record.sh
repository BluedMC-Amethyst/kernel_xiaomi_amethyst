#!/system/bin/sh
# BluedMC AutoFDO: record kernel CPU samples on amethyst (run as root on the phone).
#   adb push afdo_record.sh /data/local/tmp/
#   adb shell 'su -c "sh /data/local/tmp/afdo_record.sh 300"'      # seconds; USE THE PHONE NORMALLY meanwhile
#   adb pull /sdcard/bluedmc-afdo
# Only kernel-mode samples are recorded (cpu-cycles:k): no app data, no user-space addresses.
DUR=${1:-300}
OUT=/sdcard/bluedmc-afdo
mkdir -p $OUT; rm -f $OUT/*
old_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid)
old_kptr=$(cat /proc/sys/kernel/kptr_restrict)
setprop security.perf_harden 0
echo -1 > /proc/sys/kernel/perf_event_paranoid
echo 0 > /proc/sys/kernel/kptr_restrict
uname -r > $OUT/uname.txt
grep -E ' (_text|_stext|_etext)$' /proc/kallsyms > $OUT/kallsyms_text.txt
echo "Recording kernel samples for ${DUR}s - use the phone normally (apps, scrolling, camera, games)..."
simpleperf record -a -e cpu-cycles:k -f 4000 --duration "$DUR" -o /data/local/tmp/bmc_afdo.data
echo "Exporting..."
simpleperf report -i /data/local/tmp/bmc_afdo.data --dsos '[kernel.kallsyms]' --sort vaddr_in_file \
  -n --percent-limit 0 --full-callgraph 2>/dev/null > $OUT/report_vaddr.txt
simpleperf report -i /data/local/tmp/bmc_afdo.data --dsos '[kernel.kallsyms]' --sort symbol -n \
  --percent-limit 0.05 2>/dev/null > $OUT/report_symbols.txt
cp /data/local/tmp/bmc_afdo.data $OUT/perf.data
echo $old_paranoid > /proc/sys/kernel/perf_event_paranoid
echo $old_kptr > /proc/sys/kernel/kptr_restrict
setprop security.perf_harden 1
rm -f /data/local/tmp/bmc_afdo.data
ls -la $OUT
echo "Done. Now on the PC:  adb pull /sdcard/bluedmc-afdo"
