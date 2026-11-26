#!/system/bin/sh
# BluedMC AutoFDO: record kernel CPU samples on amethyst (run as root on the phone).
# Easiest: install the BluedMC AutoFDO KernelSU module and use its WebUI. By hand:
#   adb push afdo_record.sh /data/local/tmp/
#   adb shell 'su -c "sh /data/local/tmp/afdo_record.sh 900"'      # seconds; USE THE PHONE NORMALLY meanwhile
#   adb pull /sdcard/bluedmc-afdo
# Automated:  push afdo_workload.sh too, then   sh /data/local/tmp/afdo_record.sh 1800 workload
#             (the phone runs a repeatable, safe app + I/O + binder workload while recording; keep it
#             unlocked and on USB)
# Unplugged session (use the phone anywhere, pull later):
#   adb shell 'su -c "nohup sh /data/local/tmp/afdo_record.sh 3600 >/sdcard/afdo-run.log 2>&1 &"'
# Stop early (keeps what was recorded so far): kill -TERM the simpleperf pid in /data/local/tmp/bmc_afdo.state
# Only kernel-mode samples are recorded (cpu-cycles:k): no app data, no user-space addresses.
DUR=${1:-300}
MODE=${2:-manual}; [ "$MODE" = workload ] || MODE=manual
STATE=/data/local/tmp/bmc_afdo.state
DATA=/data/local/tmp/bmc_afdo.data
if [ -f $STATE ] && kill -0 "$(sed -n 's/^pid=//p' $STATE)" 2>/dev/null; then
  echo "a recording is already running"; exit 1
fi
if [ -n "$AFDO_BASE" ]; then BASE=$AFDO_BASE
elif [ -d /sdcard/Android ]; then BASE=/sdcard/bluedmc-afdo
else BASE=/data/media/0/bluedmc-afdo; fi
# every recording gets its own folder, so sessions can be collected and merged later
OUT=$BASE/$(date +%Y%m%d-%H%M%S)
mkdir -p $OUT
# long sessions: lower sample rate (smaller file, same coverage over time)
FREQ=${FREQ:-$([ "$DUR" -ge 1800 ] && echo 1000 || echo 4000)}
START=$(date +%s); SP=
st(){ printf 'pid=%s\nphase=%s\nstart=%s\ndur=%s\nmode=%s\nfreq=%s\nout=%s\nsp=%s\n' \
        $$ "$1" $START $DUR $MODE $FREQ $OUT "$SP" > $STATE; }
st starting
old_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid)
old_kptr=$(cat /proc/sys/kernel/kptr_restrict)
setprop security.perf_harden 0
echo -1 > /proc/sys/kernel/perf_event_paranoid
echo 0 > /proc/sys/kernel/kptr_restrict
uname -r > $OUT/uname.txt
cat /proc/version > $OUT/version.txt
# _text gives the KASLR offset; the other symbols fingerprint the exact build (to pick its vmlinux)
grep -E ' (_text|_stext|_etext|__start_rodata|linux_banner|_end|schedule|__schedule|do_idle|kmem_cache_alloc|f2fs_file_read_iter|LZ4_decompress_safe|tcp_sendmsg|binder_ioctl|handle_mm_fault)$' /proc/kallsyms > $OUT/kallsyms_text.txt
WLP=
if [ "$MODE" = workload ]; then
  WL=$(dirname "$0")/afdo_workload.sh
  [ -f "$WL" ] || { echo "afdo_workload.sh not found next to this script"; rm -f $STATE; exit 1; }
  echo "Recording ${DUR}s with the automated workload (keep the phone unlocked, don't touch it)..."
  sh "$WL" $((DUR / 60)) > $OUT/workload.log 2>&1 &
  WLP=$!
else
  echo "Recording kernel samples for ${DUR}s - use the phone normally (apps, scrolling, camera, games)..."
fi
simpleperf record -a -e cpu-cycles:k -f "$FREQ" --duration "$DUR" -o $DATA &
SP=$!; st recording
wait $SP
if [ -n "$WLP" ] && kill -0 $WLP 2>/dev/null; then      # stopped early: end the workload too
  kill $WLP 2>/dev/null; pkill -f afdo_workload.sh 2>/dev/null
  rm -rf /data/local/tmp/bmc_wl; svc power stayon false; input keyevent KEYCODE_HOME
fi
wait
ELAPSED=$(( $(date +%s) - START ))
st exporting
echo "Exporting..."
simpleperf report -i $DATA --dsos '[kernel.kallsyms]' --sort vaddr_in_file \
  -n --percent-limit 0 --full-callgraph 2>/dev/null > $OUT/report_vaddr.txt
simpleperf report -i $DATA --dsos '[kernel.kallsyms]' --sort symbol -n \
  --percent-limit 0.05 2>/dev/null > $OUT/report_symbols.txt
[ "${KEEP_DATA:-0}" = 1 ] && cp $DATA $OUT/perf.data   # raw data is large and not needed
echo "$MODE ${ELAPSED}s f=${FREQ} planned=${DUR}s" > $OUT/session.txt
echo $old_paranoid > /proc/sys/kernel/perf_event_paranoid
echo $old_kptr > /proc/sys/kernel/kptr_restrict
setprop security.perf_harden 1
rm -f $DATA
case $OUT in /data/media/*) chown -R 1023:1023 $OUT; restorecon -R $OUT 2>/dev/null;; esac
rm -f $STATE
ls -la $OUT
echo "Done: $OUT. On the PC:  adb pull /sdcard/bluedmc-afdo"
