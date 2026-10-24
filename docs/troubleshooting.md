# Troubleshooting

## XLEN mismatch

Symptom: the upload completes and `done!` is printed, but OpenSBI produces no
output; JTAG shows `mcause=1` (instruction access fault) with `mepc` inside
`0x8000xxxx`.

The board is running a bitstream of the other width (often because QSPI holds a
64-bit image and `.bit -r` reloaded it). Flash/load the matching bitstream and
verify `hart.xlen`:

```bash
printf "riscv info\n" | nc -q 1 localhost 4444 | grep hart.xlen
```

## DMA / DDR writes from the ROM seem lost

Verify with SBA first (`mww 0x80000000 0xCAFEBABE`, `mdw 0x80000000 1`). A
small payload test (e.g. `bytes(range(64))`) should read back at
`0x80000000` after an update.

## Kernel build: `arch/riscv/configs/defconfig_defconfig` not found

Buildroot appends `_defconfig` to `BR2_LINUX_KERNEL_DEFCONFIG`. For the generic
config use:

```
BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG=y
```

## `vgacon.c: undefined reference to screen_info`

The RISC-V defconfig enables `CONFIG_VGA_CONSOLE`, which is x86-only. Add:

```
# CONFIG_VGA_CONSOLE is not set
# CONFIG_FRAMEBUFFER_CONSOLE is not set
```

## `modpost: alloc_mdio_bitbang undefined`

The lowRISC Ethernet driver uses the bit-banged MDIO helper:

```
CONFIG_MDIO_BITBANG=y
```

## Kernel Image is 20+ MB

`CONFIG_STRICT_KERNEL_RWX=y` aligns sections to 4 MB and the raw `Image` pads
the holes. Disable it for this bring-up; `Image.gz` is much smaller but OpenSBI
`fw_payload` does not decompress it.

## Initramfs still large / stale modules

Buildroot does not delete removed files from `br-out*/target/`. After changing
options such as `CONFIG_MODULES`, remove the stale tree:

```bash
rm -rf br-out32/target/lib/modules br-out32/build/linux-*
```

## OpenOCD abstract commands time out

`abstractcs=...1002` / `...1102` (busy): the 32-bit DM can wedge after abstract
accesses. Reset it:

```
riscv dmi_write 0x10 0x0
riscv dmi_write 0x10 0x1
```

and prefer SBA memory commands (`mdw`, `mww`, `load_image`) over `reg`.

## `unable to open ftdi device` when flashing

Another process holds the FTDI: an OpenOCD instance, a running uploader or
picocom. Check `pgrep -x openocd`, `pgrep -f boot_uart.py`, and
`fuser /dev/ttyUSB5`; stop them before `openFPGALoader`.

## Upload stuck at 0%

The script reports every 1% now; with the older version the first update was at
10% (~3 min). At 57600 the whole 32-bit payload takes ~30 minutes. Ensure only
one process reads `/dev/ttyUSB5`.

## Ethernet module probe with the current bitstream

Do **not** `insmod lowrisc_100MHz.ko` until the bitstream includes the MAC:
there is no device at `0x30000000`, and probing would hit an unmapped address.
