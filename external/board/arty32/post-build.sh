#!/bin/sh
# Keep the initramfs small: only the lowRISC Ethernet module is needed.
set -e
if [ -d "${TARGET_DIR}/lib/modules" ]; then
    find "${TARGET_DIR}/lib/modules" -name '*.ko' ! -name 'lowrisc_100MHz.ko' -delete
fi
