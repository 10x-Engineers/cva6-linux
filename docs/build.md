# Building

Two independent dimensions:

- **XLEN**: `32` (rv32imac / ilp32) or `64` (rv64imac / lp64), both soft-float.
- **Board**: hardware profile (DTS, memory, UART, boot mode, bitstream).

```bash
make build32          # the default board
make build64
make XLEN=64 build
```

## Toolchain and versions

Pinned in `build.sh`:

| Component | Version |
|---|---|
| Buildroot | `2024.02.13` |
| OpenSBI | `v1.5.1` |
| Linux | Buildroot's default for that release (`6.6.x`) |

Buildroot builds its own cross toolchain per width inside `br-out<XLEN>/host`.

## Trees

```
buildroot/                  pinned source (shared)
opensbi/                    pinned source (shared)
br-out32/                   Buildroot output, 32-bit
br-out64/                   Buildroot output, 64-bit
opensbi-out32/              OpenSBI output, 32-bit
opensbi-out64/              OpenSBI output, 64-bit
out/arty32-fw_payload.bin   deliverable
out/arty64-fw_payload.bin   deliverable
```

`br-out*/` is disposable: `make clean` removes it; a rebuild recreates it.

## Kernel configuration

Base config is the architecture defconfig (`rv32` for 32-bit, the arch default
for 64-bit), plus `external/board/arty<XLEN>/linux.fragment`:

- `CONFIG_FPU=n` — no FPU in the bitstream; userland is soft-float.
- `CONFIG_STRICT_KERNEL_RWX=n` — avoids 4 MB section padding that inflates the
  Image (21 MB → ~6–9 MB).
- `CONFIG_NET`, `CONFIG_MODULES`, lowRISC Ethernet driver as module.
- `CONFIG_MDIO_BITBANG=y` — required by the lowRISC driver.
- `CONFIG_RISCV_EMULATED_UNALIGNED_ACCESS=n` — CVA6 traps unaligned accesses.
- DRM/VGA/FB/SCSI/ATA/USB/MMC/NFS/BTRFS disabled to keep the payload small.

## Ethernet driver patch

`external/patches/linux/` carries the lowRISC 100 MHz Ethernet driver from
`openhwfoundation/cva6-sdk` (adapted to Linux 6.6 by a second patch). It is
built as a module and only kept as `lowrisc_100MHz.ko` in the initramfs.

## Rebuilding after changes

`make boot32` / `make boot64` rebuild only if the payload is older than the
defconfig, DTS, fragment or patches. Force with `make build32` / `make build64`.

Changing a Buildroot option that removes files (for example `MODULES=n` after
modules were built) does **not** clean old files from `br-out*/target/`; remove
the stale directory (or `make clean`) in that case.
