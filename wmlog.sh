#!/bin/bash
# Start the compositor with debug output and show the errors.   fix wmlog [lilith|sway]
WM=${1:-lilith}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}; mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export WLR_RENDERER=${WLR_RENDERER:-gles2} GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia
LOG=/tmp/$WM.log
echo "==> starting $WM with debug log (it closes by itself after 10 s if it works)"
if [ "$WM" = sway ]; then
	timeout 10 dbus-run-session sway --unsupported-gpu -d >"$LOG" 2>&1
else
	timeout 10 dbus-run-session lilith -d >"$LOG" 2>&1
fi
echo "==> exit code $? (124 = it was running fine until the timeout)"
grep -iE 'error|fail|egl|gbm|renderer|cannot|unable|denied' "$LOG" | grep -v 'error_' | tail -15
echo "==> full log: $LOG"
