# CVA6 32/64-bit Linux on the Digilent Arty A7-100T
#
#   make boot32     # 32-bit rv32imac / ilp32
#   make boot64     # 64-bit rv64imac / lp64 (soft-float)
#
# or select the width explicitly:  make XLEN=64 boot
#
# Both use Buildroot 2024.02.13 + OpenSBI 1.5.1 with separate build trees.

XLEN       ?= 32

ifeq ($(XLEN),64)
IMAGE       := out/arty64-fw_payload.bin
DEFCONFIG   := arty64_defconfig
else
IMAGE       := out/arty32-fw_payload.bin
DEFCONFIG   := arty32_defconfig
endif

PORT       ?= /dev/ttyUSB5
BAUD       ?= 57600
CVA6       ?= ../cva6
BITSTREAM  ?= $(CVA6)/corev_apu/fpga/work-fpga/ariane_xilinx.bit
RESET_CMD  ?= openFPGALoader -b arty_a7_100t $(BITSTREAM)

.PHONY: build build32 build64 boot boot32 boot64 console clean distclean

build:
	./build.sh $(XLEN)

build32:
	$(MAKE) build XLEN=32

build64:
	$(MAKE) build XLEN=64

$(IMAGE): build.sh external/configs/$(DEFCONFIG) \
          external/board/arty$(XLEN)/arty$(XLEN).dts \
          external/board/arty$(XLEN)/linux.fragment \
          $(wildcard external/patches/linux/*.patch)
	./build.sh $(XLEN)

boot: $(IMAGE)
	python3 scripts/boot_uart.py --port $(PORT) --baud $(BAUD) \
		--image $(IMAGE) --reset-cmd "$(RESET_CMD)"

boot32:
	$(MAKE) boot XLEN=32

boot64:
	$(MAKE) boot XLEN=64

console:
	picocom -b $(BAUD) $(PORT)

clean:
	rm -rf out br-out32 br-out64 opensbi-out32 opensbi-out64 logs/*.log

distclean: clean
	rm -rf buildroot opensbi
