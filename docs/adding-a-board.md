# Adding a board

The Linux build is board-agnostic; only the DTB, memory size, console and boot
path change. Add a profile without touching the build system.

## 1. Board profile

Create `external/board/<board>/`:

```
<board>/
├── board.mk          # board-specific variables
├── board.dts         # device tree
├── linux.fragment    # extra kernel options (optional)
└── post-build.sh     # rootfs cleanup (optional)
```

`board.mk` (example, Arty):

```make
BOARD_PRETTY        := Digilent Arty A7-100T
OPENFPGALOADER_BOARD := arty_a7_100t
UART_DEV            := /dev/ttyUSB5
UART_BAUD           := 57600
BOOT_MODE           := uart            # uart | sd | jtag
DTS                 := external/board/arty_a7_100t/board.dts
```

## 2. Device tree

Start from the existing DTS (`external/board/arty32/arty32.dts` or
`arty64/arty64.dts`) and change only:

- `memory@80000000` size (must match the MIG configuration)
- UART `clock-frequency` / `current-speed` (must match the boot ROM and host)
- `timebase-frequency` (core clock / 2)
- Ethernet PHY node (`phy-handle`, PHY model) if the board has one
- GPIO/LED nodes

Keep the CVA6 SoC addresses (`0x10000000` UART, `0x02000000` CLINT,
`0x0c000000` PLIC, `0x30000000` lowRISC MAC) unless the board's SoC changes.

## 3. Buildroot config

Copy `external/configs/arty32_defconfig` (or `arty64_defconfig`) to
`external/configs/<board>32_defconfig` and point
`BR2_LINUX_KERNEL_CUSTOM_DTS_PATH` at the new DTS.

For a long-lived multi-board repo, keep one generic defconfig per XLEN and
generate the final defconfig by concatenating the board fragment, so board
knowledge stays in `external/board/<board>/`.

## 4. Boot mode

| Boot mode | Boards | Loader |
|---|---|---|
| `uart` | Arty (no SD) | ROM update window + `scripts/boot_uart.py` |
| `sd` | Genesys2 / Nexys Video | boot ROM GPT loader, `cva6-sdk` image |
| `jtag` | any (debug) | OpenOCD + GDB `restore` |

If the board's ROM has a different baud/clock, set it in both the DTS and the
boot ROM/bitstream; `boot_uart.py` takes `--baud`.

## 5. Validate

1. Confirm XLEN: `hart.xlen` in OpenOCD must match the payload.
2. Boot and check `uname -a` (soft-float, `rv32imac`/`rv64imac`).
3. Check memory: `cat /proc/meminfo` against the DTS/MIG.
4. Check the console baud and login prompt.

## 6. Generic Makefile interface (recommended)

```make
BOARD    ?= arty_a7_100t
XLEN     ?= 32
include external/board/$(BOARD)/board.mk

BITSTREAM ?= $(CVA6)/corev_apu/fpga/work-fpga/ariane_xilinx.bit
RESET_CMD ?= openFPGALoader -b $(OPENFPGALOADER_BOARD) $(BITSTREAM)

boot:
	python3 scripts/boot_uart.py --port $(UART_DEV) --baud $(UART_BAUD) \
		--image out/$(BOARD)-$(XLEN)/fw_payload.bin --reset-cmd "$(RESET_CMD)"
```

Then `make boot BOARD=genesys2 XLEN=64`, with per-target output directories
`out/<board>-<xlen>/`.
