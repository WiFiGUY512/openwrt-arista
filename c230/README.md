# Arista C-230

A Wi-Fi 6 campus access point, the C-260's smaller sibling: a Qualcomm
IPQ8071A with its own 5 GHz (4x4) and 2.4 GHz (2x2) radios, a QCA9882 third
radio (Arista's "multifunction" radio, used here as the scan radio), a 5 GbE
port with PoE in, a 1 GbE port, a CSR8811 Bluetooth controller, a TPM 2.0 and
a USB 2.0 port. Details in [HARDWARE.md](HARDWARE.md); installing in
[INSTALL.md](INSTALL.md). Main track only (`main/build-main.sh ipq807x`):
there is no 25.12 image.

Arista's FCC filing says the C-230E, O-235 and O-235E are the same circuit;
only a C-230 was at hand.

## What works

Seen on one unit (2026-10-22) unless marked otherwise.

- **Installing.** OpenWrt in NAND slot 0 with `arista-c230-install` from the
  RAM installer, booted by its own U-Boot `bootcmd`, with Arista's system in
  slot 1 as the fallback. Booting by itself from NAND. (`sysupgrade` and
  the fallback booting Arista: not yet run on a unit.)
- **All three radios found.** radio1 (5 GHz, 4x4) and radio2 (2.4 GHz, 2x2)
  are the IPQ8074's (ath11k), with the unit's calibration from ART and
  Arista's board data (`ipq-wifi-arista_c-230`, its default file; for a
  country set later, the file for its group is copied from slot 1, as on the
  C-260). radio0 is the QCA9882 (ath10k-ct, 2.4/5 GHz), calibration from ART.
  Not yet: an access point on them, and airscan (packaged as on the C-260,
  not yet run on a C-230).
- **Ethernet.** lan1 (AQR114C, 2.5 Gb/s on the lab switch, 5 Gb/s capable,
  PoE in) and lan2 (AR8033, 1 Gb/s), both in `br-lan` by default. The AQR114C's
  firmware is loaded by U-Boot from NOR (`0:ETHPHYFW`), as on the C-260.
- **LEDs.** All twelve (power, LAN1, LAN2, 2.4, 5, multifunction; green and
  orange each), checked on the panel. Power green while running, orange at
  boot; each Ethernet LED green while its port has a link; each radio LED lit
  while its radio is enabled (the radio LEDs: not yet seen).
- **Reset button, USB** (a stick at 480 Mb/s), **TPM** (Infineon SLB9670, TPM
  2.0, firmware 7.85; held in reset until GPIO 62 is high, which the device
  tree does).
- **Bluetooth** (CSR8811): `arista-c230-bluetooth`, the C-260's bring-up with
  the C-230's base MAC. Seen working by hand (the stage-2 test script): 30 PS
  keys, HCI 4.2, a passive LE scan heard 15 devices in 8 s. The PS keys are
  Arista's file, which this unit's 2020 Arista system lacks: the C-260's
  worked; it goes in `/lib/firmware/csr8x11-a12-bt4.2-patch.psr`.

## What doesn't (yet)

- The power policy: on 802.3af Arista's system takes 5 GHz to 2x2 and the
  third radio to 1x1, lowers transmit power and turns Bluetooth off
  (`/etc/poe_prof.cfg`: GPIO 54 is 1 on 802.3af, GPIO 64 is 0 on DC). On
  802.3at or DC it runs everything at full power, as these images always do.
- The C-230E's external-antenna board data (`EXT_*`).
- The upstream pull request and the board-file pull request are prepared,
  not sent.

## In this directory

- `files/`: the C-230's installer (`arista-c230-install`), its board data by
  country (`13-arista-c230-board-data`), and `arista-c230-bluetooth`. The
  device itself (device tree, image, board scripts, radio LEDs) is in
  `../main/patches/openwrt/0019-0020`, its board file in qca-wireless
  (`../main/openwrt.lock`).
