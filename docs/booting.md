# Booting

The payload is OpenSBI `fw_payload` with the DTB and kernel/initramfs embedded,
loaded at `0x80000000`. OpenSBI then starts Linux at `0x80200000`.

## UART update mode (Arty, no SD)

After reset the boot ROM prints:

```
Hello World!
Hit any key to enter update mode ..........
```

Within ~10 s send any byte; the ROM answers `receiving boot image` / `size:`.
The protocol is:

1. 4 bytes, little-endian payload size
2. exactly that many payload bytes, written to `0x80000000`
3. the ROM prints ` done!` and jumps to `0x80000000` with `a1` = its own DTB
   (ignored: OpenSBI uses the DTB embedded by `FW_FDT_PATH`)

`scripts/boot_uart.py` does this and then stays attached as the console:

```bash
make boot32
make boot64
python3 scripts/boot_uart.py --port /dev/ttyUSB5 --image out/arty64-fw_payload.bin
```

At 57600 the upload is ~5.7 KB/s: about 30 min for the 32-bit payload (~10 MB)
and a little longer for 64-bit (~11 MB).

## JTAG (fast path)

OpenOCD (`scripts/openocd_arty_a7_100t_cva6.cfg`) uses the BSCANE2 USER1 TAP
and halts the hart. `scripts/boot_jtag.sh` loads the payload over system bus
access (~50 s for 12 MB) and starts it at `0x80000000`. JTAG and the UART are
separate FT2232 channels, so keep the console open in one terminal and boot from
another.

Terminal 1, console (open it first and leave it open):

```bash
make console            # picocom -b 57600 /dev/ttyUSB5
```

Terminal 2:

```bash
make jtag32             # loads the bitstream, then runs:
                        # scripts/boot_jtag.sh out/arty32-fw_payload.bin
```

1. After the bitstream loads, the console prints `Hello World!` and
   `Hit any key to enter update mode ..`. Don't press a key.
2. `boot_jtag.sh` shows OpenOCD's output and
   `>>> Uploading Linux ...`, then stays silent for ~50 s.
3. `>>> Upload complete. Starting Linux` appears, OpenOCD closes and the script
   prints `Done in N s`. On a failure it prints `FAILED` and exits non-zero
   (OpenOCD's output is also in `/tmp/openocd-arty.log`).
4. The console shows OpenSBI and the kernel log, then `arty32 login:` about
   3 minutes later.

`boot_jtag.sh` modes:

| Command | Effect |
|---|---|
| `scripts/boot_jtag.sh <image>` | load, start Linux, close OpenOCD |
| `scripts/boot_jtag.sh -k <image>` | load, start Linux, keep OpenOCD open: gdb on `:3333`, telnet on `:4444`, Ctrl+C closes |
| `scripts/boot_jtag.sh` | no image: attach only (resumes the hart, so a running Linux carries on) |

Only one program may read `/dev/ttyUSB5`: a second reader (another picocom, a
`cat` logger) steals the output and the console looks dead.

The script clears `ebreakm`/`ebreaks`/`ebreaku` first: OpenSBI probes for
semihosting with an `ebreak`, and with OpenOCD's default `ebreakm=on` that
halts the hart before OpenSBI prints anything. Don't add `verify_image`: without
a work area it reads the whole image back over JTAG (5+ minutes) and then
errors, which aborts the remaining commands.

On the 32-bit target, avoid abstract register commands after some operations
(the DM can report `abstractcs=...1002` busy); reset the DM with
`riscv dmi_write 0x10 0x0` then `0x1`, and use SBA (`mdw`/`mww`).

## Matching XLEN

The bitstream, boot ROM, payload and DTB must all be the same width. A 32-bit
payload on a 64-bit bitstream starts OpenSBI and then faults (instruction access
fault). Check before uploading:

```bash
# with OpenOCD running
printf "riscv info\n" | nc -q 1 localhost 4444 | grep hart.xlen
```

Flash or load the matching bitstream:

```bash
openFPGALoader -b arty_a7_100t work-fpga/ariane_xilinx.bit     # SRAM
openFPGALoader -b arty_a7_100t -f work-fpga/ariane_xilinx.mcs # QSPI
```

`work-fpga/` holds one bitstream at a time; use `BITSTREAM=` to select another
file for a single boot.

## Console

`/dev/ttyUSB5`, 57600 8N1. Do not open `picocom` while `boot_uart.py` runs —
two readers split the stream. Expected output:

```
OpenSBI v1.5.1
...
Linux version 6.6.x ...
Welcome to Buildroot
arty32 login:            # arty64 for the 64-bit image
```

Login: `root`, no password.
