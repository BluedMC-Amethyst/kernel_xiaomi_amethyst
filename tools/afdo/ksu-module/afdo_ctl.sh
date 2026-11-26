#!/system/bin/sh
# backend for the WebUI: status | start <seconds> [manual|workload] | stop | list | delete <name> | pack | log
D=${0%/*}
STATE=/data/local/tmp/bmc_afdo.state
LOG=/data/local/tmp/bmc_afdo.log
if [ -d /sdcard/Android ]; then SD=/sdcard; else SD=/data/media/0; fi
B=$SD/bluedmc-afdo
running(){ [ -f $STATE ] && kill -0 "$(sed -n 's/^pid=//p' $STATE)" 2>/dev/null; }
case "$1" in
status)
  echo "kernel=$(uname -r)"; echo "now=$(date +%s)"
  if running; then cat $STATE; else rm -f $STATE; echo "phase=idle"; fi ;;
start)
  running && { echo "A recording is already running"; exit 1; }
  case "$2" in ''|*[!0-9]*) echo "bad duration"; exit 2;; esac
  [ -x /system/bin/simpleperf ] || { echo "simpleperf not found"; exit 1; }
  setsid sh "$D/afdo_record.sh" "$2" "${3:-manual}" > $LOG 2>&1 < /dev/null &
  i=0; while [ $i -lt 10 ]; do running && { echo started; exit 0; }; sleep 0.3; i=$((i+1)); done
  echo "failed to start:"; tail -5 $LOG; exit 1 ;;
stop)
  running || { echo "Not recording"; exit 0; }
  sp=$(sed -n 's/^sp=//p' $STATE)
  [ -n "$sp" ] && kill -TERM "$sp" 2>/dev/null && echo "Stopping, exporting what was recorded" || echo "Still starting, try again" ;;
list)
  for d in $B/*/; do
    [ -f "$d/uname.txt" ] || continue
    n=${d%/}; n=${n##*/}
    if [ -s "$d/report_vaddr.txt" ]; then ok=ok; elif running && [ "$(sed -n 's/^out=//p' $STATE)" = "${d%/}" ]; then ok=active; else ok=incomplete; fi
    echo "$n|$(cat "$d/uname.txt")|$(cat "$d/session.txt" 2>/dev/null)|$(du -sk "$d" | cut -f1)|$ok"
  done ;;
delete)
  case "$2" in ''|*/*|.*) echo "bad name"; exit 2;; esac
  running && [ "$(sed -n 's/^out=//p' $STATE)" = "$B/$2" ] && { echo "That recording is running"; exit 1; }
  rm -rf "$B/$2" && echo "Deleted $2" ;;
pack)
  ls $B/*/report_vaddr.txt >/dev/null 2>&1 || { echo "No finished recordings"; exit 1; }
  mkdir -p $SD/Download; f=$SD/Download/bluedmc-afdo-$(date +%Y%m%d-%H%M).tar.gz
  (cd $SD && tar -czf "$f" bluedmc-afdo 2>/dev/null) || { f=${f%.gz}; (cd $SD && tar -cf "$f" bluedmc-afdo); }
  case $SD in /data/media/*) chown 1023:1023 "$f";; esac
  echo "Saved ${f#$SD/} ($(du -k "$f" | cut -f1) KB)" ;;
log) tail -n 30 $LOG 2>/dev/null ;;
*) echo "usage: status|start <s> [manual|workload]|stop|list|delete <name>|pack|log"; exit 2 ;;
esac
