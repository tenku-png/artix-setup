#!/bin/bash
# fix moegram: install the missing lottie library (libtlottie.so) for moegram.
echo "== moegram comes from: $(pacman -Qoq "$(command -v moegram)" 2>/dev/null || echo 'not a pacman package (built by hand?)')"
if doas pacman -S --needed --noconfirm tlottie 2>/dev/null; then
	echo "==> tlottie installed from the repos"
else
	for i in 1 2 3; do paru -S --needed --noconfirm tlottie && break; echo "retrying..."; sleep 3; done
fi
ls -l /usr/lib/libtlottie.so* 2>/dev/null || echo "!! libtlottie.so still missing: send a photo"
ldd "$(command -v moegram)" 2>/dev/null | grep 'not found' && echo "!! other libraries missing too (above)" || echo "==> try: moegram"
