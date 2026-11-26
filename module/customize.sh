SKIPUNZIP=0
ui_print "- BluedMC Tuning for amethyst (SM7635)"
case "$(getprop ro.board.platform)$(getprop ro.product.odm.device)" in
  *volcano*|*amethyst*) ;;
  *) abort "! Only for the Redmi Note 14 Pro+ 5G (amethyst / SM7635)";;
esac
[ -d /proc/sys/walt ] || ui_print "! /proc/sys/walt not found: WALT knobs will be skipped"
ui_print "- Default profile: balanced (stock + fq qdisc for BBRv3)"
ui_print "- Switch profiles with the module's action button"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
