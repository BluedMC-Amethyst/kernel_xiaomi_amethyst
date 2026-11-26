#!/system/bin/sh
sh "${0%/*}/afdo_ctl.sh" status | sed -n 's/^phase=/Recorder: /p'
sh "${0%/*}/afdo_ctl.sh" list | wc -l | sed 's/^/Saved recordings: /'
echo "Open the WebUI to start, stop or pack recordings."
