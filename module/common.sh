#!/system/bin/sh
# BluedMC Tuning - shared functions. Profiles: stock | balanced | performance | battery
# Every node is written only if it exists. The first time a node is touched, its stock value is saved
# to $D/orig, and "stock" writes those values back.
MODDIR=${MODDIR:-${0%/*}}
D=/data/adb/bluedmc-tuning
mkdir -p "$D"
LOG=$D/log.txt
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

save_orig(){   # save_orig <path>
  local k; k=$(echo "$1" | tr '/' '_')
  [ -f "$D/orig/$k" ] && return
  mkdir -p "$D/orig"
  { echo "$1"; cat "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'; } > "$D/orig/$k"
}
w(){           # w <path> <value...>
  local p=$1; shift
  [ -w "$p" ] || { log "skip (missing) $p"; return 0; }
  save_orig "$p"
  echo "$*" > "$p" 2>/dev/null && log "set $p = $*" || log "FAILED $p = $*"
}
restore_all(){
  local f p v
  [ -d "$D/orig" ] || return 0
  for f in "$D"/orig/*; do
    [ -f "$f" ] || continue
    p=$(sed -n 1p "$f"); v=$(sed -n 2p "$f")
    # strip [brackets] from selector-style nodes like comp_algorithm / scheduler
    v=$(echo "$v" | sed -n 's/.*\[\(.*\)\].*/\1/p;t;p' | head -1)
    [ -w "$p" ] && echo "$v" > "$p" 2>/dev/null && log "restored $p = $v"
  done
}

W=/proc/sys/walt
profile_common(){
  # BBRv3 (BluedMC default congestion control) paces best with the fq qdisc.
  # Applies to interfaces brought up after this (e.g. after a Wi-Fi reconnect).
  w /proc/sys/net/core/default_qdisc fq
}
profile_balanced(){
  restore_all
  profile_common
}
profile_performance(){
  restore_all
  profile_common
  w $W/sched_fmax_cap 2147483647 2147483647 2147483647   # no light-load cap on silver/gold
  w $W/sched_upmigrate 60 80                             # stock 71 95: move busy tasks up sooner
  w $W/sched_downmigrate 50 70                           # stock 65 85
  w $W/input_boost/input_boost_ms 200                    # stock 120
  w /sys/kernel/mm/lru_gen/min_ttl_ms 1000               # MGLRU anti-thrashing (protect working set ~1s)
}
profile_battery(){
  restore_all
  profile_common
  w $W/sched_fmax_cap 1497600 1804800 2208000            # tighter light-load caps (prime capped too)
  w $W/sched_upmigrate 80 95                             # keep tasks on little cores longer
  w $W/sched_downmigrate 70 85
  w $W/input_boost/input_boost_ms 60                     # stock 120
}
apply(){
  local p; p=$(cat "$D/profile" 2>/dev/null); p=${p:-balanced}
  case $p in stock|balanced|performance|battery) ;; *) p=balanced;; esac
  log "=== apply profile: $p (kernel $(uname -r))"
  case $p in
    stock) restore_all;;
    *) profile_$p;;
  esac
  [ -f "$MODDIR/module.prop" ] && sed -i "s/^description=.*/description=[Profile: $p] amethyst WALT\/memory\/network tuning. Action button: switch profile (stock -> balanced -> performance -> battery)./" "$MODDIR/module.prop"
  echo "$p"
}
