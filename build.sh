#!/usr/bin/env bash
# Build a bootable Linux payload for the Arty A7-100T.
#   ./build.sh 32   -> out/arty32-fw_payload.bin (rv32imac, ilp32, soft-float)
#   ./build.sh 64   -> out/arty64-fw_payload.bin (rv64imac, lp64, soft-float)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
XLEN="${1:-32}"
case "$XLEN" in
  32|64) ;;
  *) echo "usage: $0 [32|64]" >&2; exit 1 ;;
esac

BR_VERSION=2024.02.13
OSBI_VERSION=v1.5.1
BR="$ROOT/buildroot"
OSBI="$ROOT/opensbi"
BR_OUT="$ROOT/br-out$XLEN"
OSBI_OUT="$ROOT/opensbi-out$XLEN"
TOOLCHAIN_PREFIX="$BR_OUT/host/bin/riscv${XLEN}-buildroot-linux-gnu-"
DEFCONFIG="arty${XLEN}_defconfig"
if [ "$XLEN" = 32 ]; then
  # Sv32 has 4 MiB PMDs; the kernel's setup_vm BUG_ON()s on a non-4MiB base.
  PAYLOAD_OFFSET=0x400000
else
  PAYLOAD_OFFSET=0x200000
fi

mkdir -p "$ROOT/out" "$ROOT/logs"

# ---------- sources ----------
if [ ! -d "$BR/.git" ]; then
  echo "[build] cloning Buildroot $BR_VERSION"
  git clone --depth 1 --branch "$BR_VERSION" \
      https://github.com/buildroot/buildroot.git "$BR"
fi
if [ ! -d "$OSBI/.git" ]; then
  echo "[build] cloning OpenSBI $OSBI_VERSION"
  git clone --depth 1 --branch "$OSBI_VERSION" \
      https://github.com/riscv-software-src/opensbi.git "$OSBI"
fi

# ---------- Buildroot ----------
echo "[build] configuring Buildroot ($DEFCONFIG, XLEN=$XLEN)"
make -C "$BR" O="$BR_OUT" BR2_EXTERNAL="$ROOT/external" "$DEFCONFIG" \
     >"$ROOT/logs/buildroot-config-$XLEN.log" 2>&1

echo "[build] building toolchain + kernel + initramfs (this takes a while)"
make -C "$BR" O="$BR_OUT" -j"$(nproc)" 2>&1 | tee "$ROOT/logs/buildroot-build-$XLEN.log"

test -f "$BR_OUT/images/Image"
test -f "$BR_OUT/images/arty${XLEN}.dtb"
test -x "${TOOLCHAIN_PREFIX}gcc"

# ---------- OpenSBI fw_payload ----------
echo "[build] building OpenSBI ($OSBI_VERSION, generic, rv$XLEN)"
make -C "$OSBI" O="$OSBI_OUT" \
     CROSS_COMPILE="$TOOLCHAIN_PREFIX" \
     PLATFORM=generic \
     FW_TEXT_START=0x80000000 \
     FW_PAYLOAD_OFFSET=$PAYLOAD_OFFSET \
     FW_PAYLOAD_PATH="$BR_OUT/images/Image" \
     FW_FDT_PATH="$BR_OUT/images/arty${XLEN}.dtb" \
     2>&1 | tee "$ROOT/logs/opensbi-build-$XLEN.log"

cp "$OSBI_OUT/platform/generic/firmware/fw_payload.bin" "$ROOT/out/arty${XLEN}-fw_payload.bin"
cp "$BR_OUT/images/arty${XLEN}.dtb" "$ROOT/out/arty${XLEN}.dtb"
cp "$BR_OUT/images/Image" "$ROOT/out/arty${XLEN}-Image"

echo
echo "[build] done (XLEN=$XLEN):"
ls -lh "$ROOT/out/arty${XLEN}-fw_payload.bin" "$ROOT/out/arty${XLEN}.dtb" "$ROOT/out/arty${XLEN}-Image"
echo "[build] boot with:  make boot XLEN=$XLEN"
