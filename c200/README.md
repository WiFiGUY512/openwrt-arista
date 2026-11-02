# Arista C-200

A Wi-Fi 6 ceiling access point: a Qualcomm IPQ6010 (the W-318's SoC) with
its own 2.4 GHz and 5 GHz radios (2x2 each), one Gigabit port (AR8033 on
SGMII, 802.3af PoE in), 32 MiB SPI NOR, 512 MiB NAND, 1 GiB RAM and an
Infineon SLB9670 TPM 2.0. No scan radio, Bluetooth or USB. Installing in
[INSTALL.md](INSTALL.md). Main track only (`main/build-main.sh ipq60xx`,
with the W-318): there is no 25.12 image.

Arista's end-of-sale notice lists a C-200P too; only a C-200 was at hand.

## What works

Seen on one unit (2026-11-01/02) unless marked otherwise.

- **Installing.** OpenWrt in NAND slot 0 as UBI, booted by its own U-Boot
  `bootcmd`, with Arista's system in slot 1 (NOR `HL_backup1`, NAND
  `rootfs_1`) as the fallback. Booting by itself from NAND, settings kept
  across reboots, `sysupgrade` keeping settings. The fallback booting
  Arista from slot 1: run once by hand (`run arista_args ubootscript`).
- **Both radios** (ath11k), with the unit's calibration from ART and Arista's
  board data (`ipq-wifi-arista_c-200`: its US file with the regulatory table
  of its own CE file, which the public firmware can read; see
  openwrt/firmware_qca-wireless#191). Access points on 2.4 GHz (HE20,
  channel 1) and 5 GHz (HE80, channel 100 after a clean 60 s CAC), WPA3, a
  client at VHT MCS 9, 80 MHz, 2 streams. US rules from the board data:
  2402-2472, 5170-5330, 5490-5730 (DFS) and 5735-5835 MHz.
- **Ethernet.** lan1 at 1 Gb/s, MAC from ART (the label MAC), in `br-lan`
  with DHCP: TCP 943 Mbit/s out with no retransmits, 941 in, from -108
  (0075). Before 0075 the port's TX clock ran from the UNIPHY RX clock
  and about 0.5% of sent frames broke (B132, openwrt/openwrt#26414).
- **LEDs.** All eight (power, 2.4, 5, LAN; green and red each), checked on
  the panel. Power green while running, red while booting, in failsafe and
  during an upgrade; LAN green with a link; 2.4 and 5 green while their
  radio is up.
- **Reset button** (GPIO 19).
- **TPM.** TPM 2.0 (firmware 7.85); `tpm2_getrandom` and the PCR banks
  answer through `/dev/tpmrm0`.

## Upstream

- Device: openwrt/openwrt#26410 (here as `main/patches/openwrt/0073-0074`).
- Board data: openwrt/firmware_qca-wireless#191.
