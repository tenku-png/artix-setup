# PipeWire voice setup (replaces easyeffects)

- `pipewire.conf.d/50-mic-clean.conf`: DeepFilterNet noise suppression
  (same plugin easyeffects used, post filter beta 0.02) exposed as the
  virtual source **Clean Mic**. Select it as the microphone in apps.
- `../../bin/mic-monitor`: toggle hearing yourself (pw-loopback from Clean
  Mic to the speakers/headphones). Bound to a key in the WM configs.

```sh
doas pacman -S --needed pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
paru -S libdeep_filter_ladspa-bin
mkdir -p ~/.config/pipewire/pipewire.conf.d
cp pipewire.conf.d/50-mic-clean.conf ~/.config/pipewire/pipewire.conf.d/
doas install -m755 ../../bin/mic-monitor /usr/local/bin/
```

Not ported from easyeffects (yet): autotune/pitch on the mic and the
equalizer/compressor/limiter on the output.
