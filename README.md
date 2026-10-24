# cva6-linux

Linux on the CVA6 RISC-V core / Digilent Arty A7-100T (32- and 64-bit), built
with pinned Buildroot + OpenSBI and booted over UART or JTAG.

Repeatable workspace for booting Linux on the Digilent Arty A7-100T, with
matching bitstreams/configs for both widths:

```bash
make boot32      # rv32imac / ilp32 soft-float, cv32a6_imac_sv32
make boot64      # rv64imac / lp64 soft-float,  cv64a6_imac_sv39
```

Everything is pinned; builds and boots are driven from the same Makefile, with
independent Buildroot/OpenSBI trees per width.

## Documentation

| Document | Contents |
|---|---|
| [docs/boards/arty_a7_100t.md](docs/boards/arty_a7_100t.md) | board profile: clocks, memory, UART, bitstreams, limitations |
| [docs/build.md](docs/build.md) | versions, build trees, kernel config, Ethernet patch |
| [docs/booting.md](docs/booting.md) | UART update protocol, JTAG boot, XLEN matching |
| [docs/adding-a-board.md](docs/adding-a-board.md) | adding another CVA6 FPGA board |
| [docs/troubleshooting.md](docs/troubleshooting.md) | known failures and fixes |

Suggested repository name: **`cva6-linux`** (board profiles live under
`docs/boards/` and `external/board/`).

```
cva6-linux-arty/
├── build.sh                     # ./build.sh 32|64 -> out/arty<XLEN>-fw_payload.bin
├── Makefile                     # make boot32 / make boot64
├── external/                    # BR2_EXTERNAL tree
│   ├── configs/arty{32,64}_defconfig
│   └── board/arty{32,64}/{arty<XLEN>.dts,linux.fragment,post-build.sh}
├── scripts/boot_uart.py         # boot ROM UART uploader + console
├── buildroot/                   # pinned Buildroot 2024.02.13 (cloned)
├── opensbi/                     # pinned OpenSBI v1.5.1 (cloned)
├── br-out32/ , br-out64/        # per-width Buildroot build trees
└── opensbi-out32/ , opensbi-out64/
```

## Hardware target

| Item | 32-bit | 64-bit |
|---|---|---|
| Bitstream | `work-fpga/ariane_xilinx.bit` | `work-fpga/ariane_xilinx.bit` |
| Core | CV32A6, RV32IMA+C, SV32 | CV64A6, RV64IMA+C, SV39 |
| ABI / FPU | `ilp32`, no FPU | `lp64`, no FPU (`CONFIG_FPU=n`) |
| RAM | 256 MB at `0x80000000` | 256 MB at `0x80000000` |
| UART | 8250 at `0x10000000`, **57600 8N1**, `/dev/ttyUSB5` | same |
| CLINT / PLIC | `0x02000000` / `0x0c000000` | same |

`work-fpga/` holds **one** bitstream at a time. Put the width you want to boot
there (or override with `make boot64 BITSTREAM=/path/to/ariane_xilinx.bit`);
the width of the payload and the bitstream must match.

## Prerequisites

Host tools: `make gcc g++ bison flex bc cpio rsync wget patch unzip file perl
python3 git dtc`, plus `python3-pyserial`. No sudo is needed.

First build needs network access (it clones Buildroot and OpenSBI) and about
2 GB of disk space.

## Paths and environment

Everything has a default, but these are the knobs:

| Variable | Default | Meaning |
|---|---|---|
| `XLEN` | `32` | selects the width; `make XLEN=64 boot` == `make boot64` |
| `CVA6` | `../cva6` | path to the CVA6 repository |
| `IMAGE` | `out/arty$(XLEN)-fw_payload.bin` | payload built/uploaded for the selected width |
| `BITSTREAM` | `$(CVA6)/corev_apu/fpga/work-fpga/ariane_xilinx.bit` | bitstream used to program/reset the board (put the matching width there, or override) |
| `RESET_CMD` | `openFPGALoader -b arty_a7_100t $(BITSTREAM)` | command that loads the bitstream (also resets the design) |
| `PORT` | `/dev/ttyUSB5` | FT2232 UART channel (Digilent `if01`) |
| `BAUD` | `57600` | UART baud rate (matches the boot ROM and the kernel DTB) |

Example with a different CVA6 checkout or serial port:

```bash
make XLEN=64 CVA6=/home/ravi-server/work/debug_work/cva6 boot
make PORT=/dev/ttyUSB7 boot32
```

Other paths used by the optional debug flow (JTAG):

| Variable / path | Default | Meaning |
|---|---|---|
| `OPENOCD_CFG` | `/home/ravi-server/work/debug_work/riscv-dbg-vip/cva6_sim/configs/openocd_arty_a7_100t_cva6.cfg` | OpenOCD config (BSCANE2 USER1 TAP, halts the hart) |
| `GDB` | `/home/ravi-server/tools/lowrisc-toolchain-gcc-rv32imcb-x86_64-20250611-1/bin/riscv-none-elf-gdb` | RISC-V GDB (or `gdb-multiarch`) |
| `RISCV` | lowRISC `riscv32imcb` toolchain | only needed if you rebuild the *bitstream*, not for Linux |
| Vivado | `/tools/Xilinx/Vivado/2024.2/settings64.sh` | only for FPGA/bitstream builds |
| `openFPGALoader` | system binary | programs/resets the board |

The Buildroot toolchain is built **inside this workspace** (`br-out/host/bin/`);
you do not need an external RISC-V Linux toolchain. The clones live in
`buildroot/` and `opensbi/` and are pinned by `build.sh`
(Buildroot `2024.02.13`, OpenSBI `v1.5.1`).

`make distclean` removes the clones; `make clean` removes `br-out/`,
`opensbi-out/`, `out/` and logs but keeps the clones.

## Build

```bash
make build32     # -> out/arty32-fw_payload.bin
make build64     # -> out/arty64-fw_payload.bin
```

Each width has its own build trees (`br-out32/`, `br-out64/`,
`opensbi-out32/`, `opensbi-out64/`) and:

1. builds **Buildroot 2024.02.13** with `arty32_defconfig` (rv32imac / ilp32)
   or `arty64_defconfig` (rv64imac / lp64), glibc, soft-float, 8250 console,
   initramfs,
2. builds the kernel (`rv32` defconfig / `defconfig` plus the matching
   `linux.fragment`) with `arty<XLEN>.dts`,
3. builds **OpenSBI v1.5.1** `fw_payload` for the `generic` platform with the
   kernel and DTB embedded (`FW_FDT_PATH`),
4. copies the result to `out/arty<XLEN>-fw_payload.bin`.

First build per width is long (toolchain + kernel). Later builds are
incremental.

## Boot over UART (primary path, no JTAG)

```bash
make boot32              # 32-bit, /dev/ttyUSB5, 57600
make boot64              # 64-bit
# or, if the board is already reset:
python3 scripts/boot_uart.py --port /dev/ttyUSB5 --image out/arty64-fw_payload.bin
```

`make boot32`/`boot64` only rebuild the payload if it is missing or older than
the config/DTS/fragment/patch files; otherwise they go straight to uploading.
Use `make build32`/`build64` to force a rebuild.

The reset command loads the matching bitstream:
`openFPGALoader -b arty_a7_100t $(BITSTREAM)` (override with `RESET_CMD=...`).
It then:

1. waits for `Hit any key to enter update mode` (10 s window),
2. sends a key, then the 4-byte little-endian payload size and the payload,
3. the boot ROM writes it to `0x80000000` and jumps,
4. the script keeps printing the console: OpenSBI -> Linux -> login.

At 57600 the upload runs at ~5.7 KB/s: the 32-bit payload (~10 MB) takes
~30 minutes, the 64-bit payload somewhat longer.
The console is the same UART, so no reconnection is needed.

Reset alternatives for `RESET_CMD`:

```bash
# load the bitstream in work-fpga (default)
make boot32

# if you prefer to reset the board yourself (PROG button / power cycle):
make boot32 RESET_CMD=true

# or load another bitstream:
make boot64 RESET_CMD="openFPGALoader -b arty_a7_100t /path/to/ariane_xilinx.bit"
```


Expected start:

```
Hello World!
Hit any key to enter update mode ..........
 updating!
receiving boot image
size: ...
receiving ................ done!
OpenSBI v1.5.1
...
Linux version 6.x ...
Welcome to Buildroot
arty32 login:              # arty64 for the 64-bit payload
```

Login as `root` (no password; set `BR2_TARGET_GENERIC_ROOT_PASSWD` to change).

## Boot over JTAG (optional, much faster)

Start OpenOCD with the Arty config (it halts the hart):

```bash
openocd -f /home/ravi-server/work/debug_work/riscv-dbg-vip/cva6_sim/configs/openocd_arty_a7_100t_cva6.cfg
```

Then, from another terminal (use `riscv:rv64` and `arty64-...` for the 64-bit
payload):

```bash
/home/ravi-server/tools/lowrisc-toolchain-gcc-rv32imcb-x86_64-20250611-1/bin/riscv-none-elf-gdb -q
(gdb) set architecture riscv:rv32        # riscv:rv64 for 64-bit
(gdb) target extended-remote :3333
(gdb) restore out/arty32-fw_payload.bin binary 0x80000000   # arty64-... for 64-bit
(gdb) set $pc = 0x80000000
(gdb) set $a0 = 0
(gdb) set $a1 = 0
(gdb) continue
```

OpenSBI uses the DTB embedded in the payload (`FW_FDT_PATH`), so the boot ROM's
own DTB is not used. This path is independent of the UART boot ROM update mode;
the console is still `/dev/ttyUSB5` at 57600.

## Ethernet (enabled now, usable with a future bitstream)

The Arty A7-100T has a 10/100 PHY, but the current bitstream leaves the
lowRISC MAC disabled (`InclEthernet(1'b0)`). The Linux image therefore builds
the MAC driver as a **module** so it is inert until the hardware exists:

```
/lib/modules/6.6.84/kernel/drivers/net/ethernet/lowrisc/lowrisc_100MHz.ko
```

The device tree already contains the node (`ethernet@30000000`). Once a
bitstream with the MAC/pins is loaded, no Linux rebuild is needed:

```sh
insmod /lib/modules/6.6.84/kernel/drivers/net/ethernet/lowrisc/lowrisc_100MHz.ko
ifconfig eth0 up
udhcpc -i eth0                  # or: ifconfig eth0 192.168.1.50 netmask 255.255.255.0
```

Do **not** load the module with the current bitstream: there is no MAC at
`0x30000000`, so probing would access an unmapped AXI address.

Driver source: `external/patches/linux/0001-lowrisc-eth.patch` (from
`openhwfoundation/cva6-sdk`, adapted to 6.6 by `0002-lowrisc-eth-6.6-remove.patch`).
The post-build script keeps only this module in the initramfs.

## Kernel/rootfs details

- 32-bit: `BR2_RISCV_32`, ABI `ilp32`; 64-bit: `BR2_RISCV_64`, ABI `lp64`.
  Both use `BR2_riscv_custom`, I/M/A/C, soft-float.
- No F/D in either bitstream: hard-float (`ilp32d`/`lp64d`) userland would trap.
- `BR2_TARGET_ROOTFS_INITRAMFS=y` bakes BusyBox into the kernel Image.
- `CONFIG_RISCV_EMULATED_UNALIGNED_ACCESS=n` (CVA6 traps unaligned accesses;
  emulation caused problems for Codethink on this core).
- `CONFIG_FPU=n` so the kernel does not context-switch FP state.

## Changing things

| Want to change | Where |
|---|---|
| console baud / getty | `external/board/arty$(XLEN)/arty$(XLEN).dts` and `arty$(XLEN)_defconfig` |
| kernel options | `external/board/arty$(XLEN)/linux.fragment` |
| memory/UART/CLINT/PLIC | `external/board/arty$(XLEN)/arty$(XLEN).dts` |
| Buildroot packages | `external/configs/arty$(XLEN)_defconfig` |
| UART port | `make boot32 PORT=/dev/ttyUSBx` |

## Troubleshooting

- **Board runs the wrong design / 32-bit payload traps immediately**: check
  `hart.xlen` in OpenOCD. `openFPGALoader ... .bit -r` loads SRAM and then
  resets the FPGA, which can re-configure it from QSPI — if the flash holds a
  different image (e.g. 64-bit), that is what runs. Flash the matching
  `.mcs` (`openFPGALoader -b arty_a7_100t -f -r ...mcs`) and confirm
  `hart.xlen` is 32 before uploading a 32-bit payload.
- **`openocd` `reg`/`riscv info` time out with `abstractcs=...1002`**: the
  32-bit DM's abstract-command path wedges after some operations. Reset the DM
  (`riscv dmi_write 0x10 0x0`, then `0x1`) and use SBA memory access
  (`mdw`/`mww`) instead of abstract register commands.
- **No `Hit any key`**: wrong port/baud, or the board was reset before the
  script started. `make boot` reprograms the bitstream to guarantee a reset.
- **`size:` but no progress**: another process owns `/dev/ttyUSB5` (close
  picocom/screen).
- **Upload is slow**: expected at 57600; use the JTAG path for iteration.
- **Kernel panics at boot**: check the DTB (`dtc -I dtb -O dts out/arty32.dtb`)
  and that `CONFIG_FPU=n`; capture the full log from the script output.
- **No login prompt**: initramfs is built into `Image`; confirm
  `BR2_TARGET_ROOTFS_INITRAMFS=y` and that Buildroot's `rootfs.cpio` was used.

## Reproducibility

Pinned: Buildroot `2024.02.13`, OpenSBI `v1.5.1`, kernel = Buildroot's
`BR2_LINUX_KERNEL_LATEST_VERSION` for that release. The bitstream is taken from
`corev_apu/fpga/work-fpga/` (32- or 64-bit, matching the payload).
