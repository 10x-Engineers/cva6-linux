#!/usr/bin/env python3
"""Upload a payload through the Arty boot ROM's UART update mode and stay
attached as the console.

Protocol (see corev_apu/fpga/src/bootrom/src/main.c):
  1. after reset the ROM prints "Hit any key to enter update mode" and waits
     10 s, sending one '.' per second
  2. send any byte
  3. the ROM prints "receiving boot image\\r\\nsize: "
  4. send 4-byte little-endian length, then the payload bytes
  5. the ROM writes it to 0x80000000, prints " done!" and jumps
"""

import argparse
import os
import struct
import subprocess
import sys
import time

import serial


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB5")
    ap.add_argument("--baud", type=int, default=57600)
    ap.add_argument("--image", required=True)
    ap.add_argument("--reset-cmd", default=None,
                    help="optional shell command to reset/reprogram the board")
    args = ap.parse_args()

    size = os.path.getsize(args.image)
    with open(args.image, "rb") as f:
        image = f.read()

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    ser.reset_input_buffer()
    print(f"[boot] {args.port} @ {args.baud}, payload {size} bytes "
          f"(~{size / (args.baud / 10) / 60:.1f} min)", flush=True)

    if args.reset_cmd:
        print(f"[boot] reset: {args.reset_cmd}", flush=True)
        subprocess.Popen(args.reset_cmd, shell=True)
    else:
        print("[boot] reset the board now (PROG button / power cycle / "
              "openFPGALoader -r)", flush=True)

    buf = b""
    key_sent = False
    size_sent = False
    deadline = time.time() + 90.0

    while True:
        chunk = ser.read(256)
        if chunk:
            sys.stdout.write(chunk.decode("utf-8", "replace"))
            sys.stdout.flush()
            buf += chunk
            deadline = time.time() + 90.0

        if not key_sent and b"Hit any key" in buf:
            ser.write(b"\r")
            key_sent = True
            print("\n[boot] key sent, waiting for size prompt", flush=True)

        if key_sent and not size_sent and b"size:" in buf:
            ser.write(struct.pack("<I", size))
            time.sleep(0.05)
            sent = 0
            next_report = 0
            t0 = time.time()
            while sent < size:
                n = ser.write(image[sent:sent + 4096])
                sent += n
                if sent >= next_report:
                    pct = 100 * sent // size
                    elapsed = time.time() - t0
                    rate = sent / elapsed if elapsed else 0
                    eta = (size - sent) / rate if rate else 0
                    print(f"\r[boot] {pct:3d}%  {sent}/{size}  "
                          f"{rate / 1024:.1f} KiB/s  ETA {eta / 60:.1f} min",
                          end="", flush=True)
                    next_report = (pct + 1) * size // 100
            ser.flush()
            size_sent = True
            print("\n[boot] upload complete, booting", flush=True)
            deadline = time.time() + 600.0

        if time.time() > deadline:
            print("\n[boot] timed out waiting for the ROM prompt", flush=True)
            return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n[boot] stopped (target keeps running)", flush=True)
        sys.exit(0)
