#!/bin/bash
# fix wpslim: wireplumber without Bluetooth and camera monitors.
# Virtual cameras (v4l2loopback / OBS) still work: apps open /dev/video* directly.
d=~/.config/wireplumber/wireplumber.conf.d; mkdir -p $d
cat > $d/90-slim.conf <<'C'
wireplumber.profiles = {
  main = {
    monitor.bluez = disabled
    monitor.bluez-midi = disabled
    monitor.libcamera = disabled
    monitor.v4l2 = disabled
  }
}
C
echo "before: $(mem)"
pkill -x wireplumber; sleep 0.5; (wireplumber >/dev/null 2>&1 &); sleep 2
echo "after:  $(mem)   (undo: rm $d/90-slim.conf)"
pgrep -x wireplumber >/dev/null && echo "==> wireplumber running" || echo "!! wireplumber did not start"
