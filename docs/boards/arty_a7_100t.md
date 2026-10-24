# Arty A7-100T board profile

Digilent Arty A7-100T (xc7a100tcsg324-1), CVA6 FPGA SoC.

## Hardware

| Item | Value |
|---|---|
| FPGA | Xilinx Artix-7 `xc7a100tcsg324-1` |
| Core clock | 25 MHz (12.5 MHz timebase) |
| DRAM | 256 MiB at `0x80000000` (MIG DDR3) |
| UART | 8250-compatible at `0x10000000`, **57600 8N1**, `/dev/ttyUSB5` |
| CLINT / PLIC | `0x02000000` / `0x0c000000` |
| Ethernet PHY | on-board 10/100 PHY; MAC currently disabled in the bitstream |
| Debug | BSCANE2 USER1 TAP (riscv-dbg), IDCODE `0x13631093` |

## Supported bitstreams

| Width | Config | Bitstream |
|---|---|---|
| 32-bit | `cv32a6_imac_sv32` | `corev_apu/fpga/work-fpga/ariane_xilinx.bit` (32-bit build) |
| 64-bit | `cv64a6_imac_sv39` | same path, after a 64-bit build (one bitstream at a time) |

Build from the CVA6 repo:

```bash
make fpga BOARD=arty_a7_100t target=cv32a6_imac_sv32
make fpga BOARD=arty_a7_100t target=cv64a6_imac_sv39
```

Both configs have **no F/D** → Linux must be soft-float (`ilp32` / `lp64`,
`CONFIG_FPU=n`).

## Boot media

The Arty has **no SD card**. The CVA6 boot ROM therefore stays in its 10-second
"hit any key" menu and accepts a **UART update**: 4-byte little-endian size
followed by the raw payload, written to `0x80000000`, then `jr 0x80000000`.

`scripts/boot_uart.py` implements this and keeps printing the console.

## Linux profile files

| File | Purpose |
|---|---|
| `external/board/arty32/arty32.dts` | 32-bit DTB (`rv32imac`, `sv32`) |
| `external/board/arty64/arty64.dts` | 64-bit DTB (`rv64imac`, `sv39`) |
| `external/configs/arty32_defconfig` | rv32imac / ilp32 / glibc |
| `external/configs/arty64_defconfig` | rv64imac / lp64 / glibc |
| `external/board/arty{32,64}/linux.fragment` | kernel options (FPU off, 8250, no DRM, …) |
| `external/board/arty{32,64}/post-build.sh` | keep only `lowrisc_100MHz.ko` |

## Known limitations

- `openFPGALoader ... .bit -r` can reload the QSPI image; use the plain `.bit`
  load, or flash the matching `.mcs` first. Verify `hart.xlen` before uploading.
- The 32-bit DM's abstract commands can wedge (`abstractcs=...1002`); reset the
  DM (`riscv dmi_write 0x10 0x0` then `0x1`) and use SBA memory access.
- Ethernet needs a future bitstream with the MAC/pins; the driver is built as a
  module and is not loaded by default.

## Flashing

```bash
# volatile (SRAM, current design)
openFPGALoader -b arty_a7_100t corev_apu/fpga/work-fpga/ariane_xilinx.bit

# persistent (QSPI)
openFPGALoader -b arty_a7_100t -f corev_apu/fpga/work-fpga/ariane_xilinx.mcs
```
