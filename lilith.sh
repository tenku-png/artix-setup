#!/bin/bash
# Rebuild lilith from tenku-png/liwm.  fix lilith  (stable)  |  fix lilith-new  (newest)
set -e
BR=${LIWM_BRANCH:-stable}
[ -d ~/liwm/.git ] || git clone https://github.com/tenku-png/liwm ~/liwm
cd ~/liwm
for i in 1 2 3; do git fetch origin "$BR" && break; echo "retrying..."; sleep 2; done
git checkout -q -B "$BR" "origin/$BR"
make clean >/dev/null 2>&1 || true
make
doas make install
echo "==> lilith ($BR, $(git log --oneline -1)) installed. Log out (Super+Shift+Alt+Q) and log in again."
