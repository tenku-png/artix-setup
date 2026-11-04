#!/bin/bash
# fix noddc: turn off DDC/CI monitor access again (suspected lilith freeze).
doas rm -f /etc/modules-load.d/i2c-dev.conf
doas modprobe -r i2c-dev 2>/dev/null
rm -f "${XDG_RUNTIME_DIR:-/tmp}"/bri.*
lsmod | grep -q '^i2c_dev' && echo "!! i2c-dev still loaded (reboot)" || echo "==> DDC/CI off. Start lilith: start-wm lilith"
