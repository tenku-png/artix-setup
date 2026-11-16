#!/bin/bash
# Compatibility command: configure the standalone AmneziaWG tunnel (no GUI).
set -euo pipefail
R="https://raw.githubusercontent.com/tenku-png/artix-setup/${REF:-main}"
exec bash <(curl -fsSL "$R/awg.sh") "$@"
