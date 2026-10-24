# cva6-linux

Linux on the CVA6 RISC-V core / Digilent Arty A7-100T (32- and 64-bit), built
with pinned Buildroot + OpenSBI and booted over UART or JTAG.

```bash
make boot32      # rv32imac / ilp32 soft-float
make boot64      # rv64imac / lp64 soft-float
```

## Documentation

| Document | Contents |
|---|---|
| [docs/boards/arty_a7_100t.md](docs/boards/arty_a7_100t.md) | board clocks, memory, UART, bitstreams |
| [docs/build.md](docs/build.md) | versions, build trees, kernel config, Ethernet patch |
| [docs/booting.md](docs/booting.md) | UART update protocol, JTAG boot, XLEN matching |
| [docs/adding-a-board.md](docs/adding-a-board.md) | adding another CVA6 FPGA board |

## Hardware target

| Item | 32-bit | 64-bit |
|---|---|---|
| Config | `cv32a6_imac_sv32` | `cv64a6_imac_sv39` |
| ISA / MMU | RV32IMA+C, SV32 | RV64IMA+C, SV39 |
| ABI | `ilp32`, soft-float | `lp64`, soft-float |
| Bitstream | `$(CVA6)/corev_apu/fpga/work-fpga/ariane_xilinx.bit` | same file (matching width) |
| RAM | 256 MiB @ `0x80000000` | same |
| Console | 8250 @ `0x10000000`, 57600 8N1, `/dev/ttyUSB5` | same |

Both bitstreams have no F/D → kernel `CONFIG_FPU=n`.

## Prerequisites

Host tools: `make gcc g++ bison flex bc cpio rsync wget patch unzip file perl
python3 git dtc`, plus `python3-pyserial`. No sudo needed. First build clones
Buildroot and OpenSBI (network required).

## Paths and variables

| Variable | Default | Meaning |
|---|---|---|
| `XLEN` | `32` | select width (`make XLEN=64 boot` == `make boot64`) |
| `CVA6` | `../cva6` | path to the CVA6 repository |
| `BITSTREAM` | `$(CVA6)/corev_apu/fpga/work-fpga/ariane_xilinx.bit` | bitstream to load (one width at a time) |
| `RESET_CMD` | `openFPGALoader -b arty_a7_100t $(BITSTREAM)` | loads the bitstream and resets the design |
| `PORT` / `BAUD` | `/dev/ttyUSB5` / `57600` | board UART |

```bash
make XLEN=64 BITSTREAM=/path/to/ariane_xilinx.bit boot
make PORT=/dev/ttyUSB7 boot32
```

## Build

```bash
make build32     # -> out/arty32-fw_payload.bin
make build64     # -> out/arty64-fw_payload.bin
```

Each width gets its own `br-out<XLEN>/` and `opensbi-out<XLEN>/`. First build is
long (toolchain + kernel); later builds are incremental. `make boot32/64`
rebuilds only if the payload is older than the config/DTS/fragment/patch files.

## Boot over UART (default)

```bash
make boot32      # or make boot64
```

This loads the bitstream, waits for the boot ROM's `Hit any key`, uploads the
payload (4-byte size + raw image) at 57600, and stays attached as the console
(OpenSBI → Linux → login `root`). At 57600 a 10 MB payload takes ~30 min.

## Boot over JTAG

With OpenOCD running (`openocd_arty_a7_100t_cva6.cfg`):

```gdb
set architecture riscv:rv32        # riscv:rv64 for 64-bit
target extended-remote :3333
restore out/arty32-fw_payload.bin binary 0x80000000
set $pc = 0x80000000
set $a0 = 0
set $a1 = 0
continue
```

## Ethernet

The lowRISC MAC driver is built as a module (`lowrisc_100MHz.ko`) and is **not**
loaded by default — the current bitstream has no MAC at `0x30000000`. Once a
bitstream with the MAC/pins is loaded:

```sh
insmod /lib/modules/6.6.84/kernel/drivers/net/ethernet/lowrisc/lowrisc_100MHz.ko
ifconfig eth0 up
udhcpc -i eth0
```

## License

Apache License 2.0 — see [LICENSE](LICENSE). Use, modify and redistribute freely,
including commercially, with attribution; no warranty.
