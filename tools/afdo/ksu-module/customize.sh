SKIPUNZIP=0
[ -x /system/bin/simpleperf ] || ui_print "! /system/bin/simpleperf not found: recording will not work on this ROM"
case "$(uname -r)" in *BluedMC*) ;; *) ui_print "! Not running a BluedMC kernel: recordings can only be turned into a profile for BluedMC builds";; esac
set_perm_recursive "$MODPATH" 0 0 0755 0644
ui_print "- Open the module's WebUI in KernelSU-Next to record"
