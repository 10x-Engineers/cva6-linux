# Networking, LED web page and GPIO

## Ethernet hardware

| Item | Value |
|---|---|
| MAC | lowRISC register interface (`framing_top_mii` in the CVA6 bitstream) at `0x30000000`, PLIC source 3 |
| PHY | TI DP83848J, 10/100 MII, MDIO address 1 |
| PHY reference clock | 25 MHz from the FPGA (`eth_ref_clk`, pin G18) |
| Linux driver | `lowrisc_100MHz.ko` (out of tree, `external/patches/linux/`) |

## Boot-time setup

`/etc/init.d/S41ethernet` (source:
`external/board/common/rootfs-overlay/etc/init.d/S41ethernet`) loads the driver
and configures eth0. Edit the variables at the top for your network:

| Variable | Default | Notes |
|---|---|---|
| `ETH_IP` | `192.168.100.200/24` | static address |
| `ETH_GW` | `192.168.100.1` | default route |
| `ETH_DNS` | `8.8.8.8` | written to `/etc/resolv.conf` |
| `NTP_SERVER` | `pool.ntp.org` | `ntpd -q` sets the clock 5 s after the link is up (no RTC) |
| `ETH_MAC` | `02:00:00:00:00:01` | the MAC's reset value `23:01:00:89:07:02` is multicast and peers drop it |
| `ETH_ADVERTISE` | `0x00f` | 10/100 autonegotiation; `0x003` = 10 Mb/s only |

Check from the board:

```sh
ethtool eth0            # speed/duplex/link
ping -c 3 192.168.100.1
date                    # set by NTP
wget -q -O - http://example.com | head
```

Plain HTTP works; there is no HTTPS client (a TLS handshake takes ~50 s of CPU
at 25 MHz, longer than most servers wait).

## Known network quirks

- **CoreChips SR9900 USB-Ethernet dongles** (USB ID `0fe6:9900`): at 100 Mb/s
  the DP83848J's receiver never locks to them (PHY registers RECR `0x15` and
  FCSCR `0x14` saturate, every frame is bad); 10 Mb/s is clean. Use a
  router/switch, or set `ETH_ADVERTISE=0x003`.
- **Two host NICs in the same subnet**: replies to the board leave through the
  NIC with the lower metric. Ping with `ping -I <nic> 192.168.100.200`.
- **Throughput** is CPU-bound: about 80 full-size frames/s at 25 MHz. Beyond
  that frames are dropped; reception recovers (driver patch 0003).
- **PHY diagnosis**: `ethtool -d eth0` dumps PHY registers 0–31 (as 32-bit
  words), then the MAC registers. PHYSTS is register `0x10`.

## LED web page

BusyBox `httpd` (started by `/etc/init.d/S50httpd`) serves
`/srv/www/index.html` on port 80. Open `http://192.168.100.200`:

- click LD4–LD7 to toggle them; *All on* / *All off*;
- SW0–SW3 are shown live (polled every 1.5 s);
- *LEDs follow switches* starts a background process that mirrors the switches
  onto the LEDs until another button is pressed.

The page talks to `/cgi-bin/led`, a small C program
(`external/package/arty-led-cgi/`), which replies with JSON:

```sh
curl http://192.168.100.200/cgi-bin/led              # read state
curl http://192.168.100.200/cgi-bin/led?toggle=2     # toggle LD6
curl http://192.168.100.200/cgi-bin/led?all=on       # or all=off
curl http://192.168.100.200/cgi-bin/led?follow=1     # or follow=0
# {"leds":15,"switches":3,"follow":0,"uptime":512}  (4-bit masks)
```

It is written in C because each fork/exec costs about a second at 25 MHz; a
shell CGI took ~8 s per request.

BusyBox 1.36.1's httpd returns 404 for `/` when CGI is enabled unless
`FEATURE_HTTPD_BASIC_AUTH` is built in, so `external/board/busybox.fragment`
enables it (no `httpd.conf`, so nothing asks for a password).

## GPIO (LEDs and switches)

A Xilinx AXI GPIO sits at `0x40000000`:

| Register | Offset | Bits |
|---|---|---|
| Channel 1 data (LEDs) | `0x0` | LD4..LD7 = bits 4..7 |
| Channel 1 direction | `0x4` | write `0` = outputs (`S50httpd` does this at boot) |
| Channel 2 data (switches) | `0x8` | SW0..SW3 = bits 4..7 |

From the shell (stop the web page's *follow* mode first):

```sh
devmem 0x40000000 32 0xF0                                   # all LEDs on
devmem 0x40000008 32                                        # read switches
while :; do devmem 0x40000000 32 $(devmem 0x40000008 32); done   # LEDs follow switches
```

Type commands rather than pasting long lines: at 25 MHz the UART drops
characters of pasted input.
