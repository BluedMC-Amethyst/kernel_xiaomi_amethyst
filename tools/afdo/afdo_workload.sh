#!/system/bin/sh
# BluedMC AutoFDO workload: repeatable, kernel-heavy activity to run WHILE afdo_record.sh records.
# Safe by design: it only opens allowlisted apps, scrolls with swipes, presses Back/Home and closes them.
# It never taps, types, or opens messaging/banking/social apps, so nothing can be sent, bought or changed.
# usage (root): sh afdo_workload.sh <minutes>
MIN=${1:-30}
END=$(( $(date +%s) + MIN * 60 ))
T=/data/local/tmp/bmc_wl
log(){ echo "[wl $(date +%H:%M:%S)] $*"; }

# screen: wake, keep awake while on USB, 120 Hz like normal use
input keyevent KEYCODE_WAKEUP
svc power stayon usb
W=$(wm size | sed -n 's/.* \([0-9]*\)x\([0-9]*\)$/\1/p'); H=$(wm size | sed -n 's/.* [0-9]*x\([0-9]*\)$/\1/p')
W=${W:-1220}; H=${H:-2712}; X=$((W/2)); Y1=$((H*3/4)); Y2=$((H/4))

# allowlist (only those installed are used). No messaging, banking, social, payment or store apps.
ALLOW="com.android.settings com.miui.gallery com.android.deskclock com.miui.calculator com.android.camera
com.miui.notes com.miui.weather2 com.android.chrome com.mi.globalbrowser com.android.browser
com.google.android.youtube com.google.android.apps.maps com.miui.player com.android.fileexplorer
com.google.android.apps.nbu.files com.android.calendar com.xiaomi.calendar com.miui.compass"
APPS=""
for p in $ALLOW; do pm path "$p" >/dev/null 2>&1 && APPS="$APPS $p"; done
log "apps: $APPS"
URLS="https://en.wikipedia.org/wiki/Linux_kernel https://en.wikipedia.org/wiki/Android_(operating_system) https://www.kernel.org https://source.android.com https://en.wikipedia.org/wiki/ARM_architecture_family"

scroll(){ i=0; while [ $i -lt $1 ]; do input swipe $X $Y1 $X $Y2 180; sleep 0.4; input swipe $X $Y2 $X $Y1 220; sleep 0.3; i=$((i+1)); done; }

app_round(){
  for p in $APPS; do
    [ $(date +%s) -ge $END ] && return
    case $p in
      com.android.chrome|com.mi.globalbrowser|com.android.browser)
        for u in $URLS; do am start -a android.intent.action.VIEW -d "$u" -p "$p" >/dev/null 2>&1; sleep 4; scroll 4; done;;
      com.android.camera)
        monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 5;;   # viewfinder only, no shutter
      *)
        monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 2.5; scroll 5;;
    esac
    input keyevent KEYCODE_BACK; sleep 0.5; input keyevent KEYCODE_HOME; sleep 0.5
    am force-stop "$p"            # next launch is a cold start: page faults, file mapping, binder
  done
}

io_round(){
  mkdir -p $T/tree
  dd if=/dev/urandom of=$T/big bs=1M count=128 2>/dev/null; sync
  cat $T/big > /dev/null; dd if=$T/big of=$T/big2 bs=64k 2>/dev/null; sync
  i=0; while [ $i -lt 400 ]; do echo $i > $T/tree/f$i; i=$((i+1)); done; sync
  ls -lR $T/tree > /dev/null; cat $T/tree/* > /dev/null; rm -rf $T/tree $T/big $T/big2
  find /system /vendor /product -type f 2>/dev/null | head -3000 | while read f; do head -c 4096 "$f" > /dev/null 2>&1; done   # EROFS lookups + LZ4 decompression
}

binder_round(){
  cmd package list packages > /dev/null; dumpsys activity activities > /dev/null 2>&1
  dumpsys meminfo -s > /dev/null 2>&1; service list > /dev/null; getprop > /dev/null
  ping -c 10 -i 0.2 1.1.1.1 > /dev/null 2>&1
}

n=0
while [ $(date +%s) -lt $END ]; do
  n=$((n+1)); log "round $n"
  app_round; io_round; binder_round
done
input keyevent KEYCODE_HOME
svc power stayon false
rm -rf $T
log "done after $n rounds"
