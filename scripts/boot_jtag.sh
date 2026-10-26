#!/usr/bin/env bash
# Fast boot over JTAG: halt the hart, write the OpenSBI fw_payload to DDR
# through the debug module's system bus access, then start it at 0x80000000.
#   scripts/boot_jtag.sh out/arty32-fw_payload.bin     load, boot, close OpenOCD
#   scripts/boot_jtag.sh -k out/arty32-fw_payload.bin  load, boot, keep OpenOCD open
#   scripts/boot_jtag.sh                               only open OpenOCD (attach)
# While OpenOCD is open: gdb on :3333, telnet on :4444. Ctrl+C closes it.
# Watch the console with:  picocom -b 57600 /dev/ttyUSB5
set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    -k|--keep) KEEP=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage 1 >&2 ;;
    *) break ;;
  esac
done
[ $# -le 1 ] || usage 1 >&2

CFG="${OPENOCD_CFG:-$(dirname "$0")/openocd_arty_a7_100t_cva6.cfg}"
LOG="${OPENOCD_LOG:-/tmp/openocd-arty.log}"
OPEN_MSG="echo {>>> OpenOCD stays open: gdb -> localhost:3333, telnet -> localhost:4444. Ctrl+C to close.};"

# No image: just attach. The config halts the hart; resume it so whatever was
# running (e.g. Linux) carries on. gdb halts it again when it connects.
if [ $# -eq 0 ]; then
  echo "No image given: starting OpenOCD only."
  exec openocd -f "$CFG" -c "resume; $OPEN_MSG"
fi

IMAGE="$(realpath "$1")"
SIZE_MB=$(( $(stat -c %s "$IMAGE") / 1048576 ))
if [ "$KEEP" -eq 1 ]; then END="$OPEN_MSG"; else END="echo {>>> Closing OpenOCD.}; shutdown"; fi

echo "Loading $(basename "$IMAGE") (${SIZE_MB} MB) into DDR over JTAG."
echo "This takes about 50 s; please wait. Don't type in the serial terminal meanwhile."

start=$SECONDS
rc=0
# OpenSBI probes for semihosting with an ebreak; with ebreakm set (OpenOCD's
# default) that ebreak halts the hart, so let it trap to M-mode instead.
openocd -f "$CFG" -c "
  riscv set_ebreakm off;
  riscv set_ebreaks off;
  riscv set_ebreaku off;
  echo {>>> Uploading Linux to 0x80000000 (~50 s, no output until done)...};
  load_image $IMAGE 0x80000000 bin;
  echo {>>> Upload complete. Starting Linux; boot continues on the serial console.};
  reg a0 0;
  reg a1 0;
  reg pc 0x80000000;
  resume;
  $END" 2>&1 | tee "$LOG" || rc=$?

# With -k the user closed OpenOCD with Ctrl+C; nothing more to report.
[ "$KEEP" -eq 1 ] && exit 0

if [ "$rc" -ne 0 ] || grep -q "^Error" "$LOG"; then
  echo "FAILED: the image was not loaded (see the OpenOCD output above, also in $LOG)."
  exit 1
fi

echo "Done in $((SECONDS - start)) s. Linux is now booting; this script is finished."
echo "Watch the serial terminal (picocom -b 57600 /dev/ttyUSB5):"
echo "the login prompt 'arty32 login:' appears in about 3 minutes. Log in as root."
