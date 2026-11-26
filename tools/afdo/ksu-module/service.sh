#!/system/bin/sh
# a reboot ends any recording; drop its stale state and data
rm -f /data/local/tmp/bmc_afdo.state /data/local/tmp/bmc_afdo.data
rm -rf /data/local/tmp/bmc_wl
