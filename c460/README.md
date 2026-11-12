# Arista C-460

A Wi-Fi 7 ceiling access point: a Qualcomm IPQ9574 (AP-AL02-C13 reference
design) with three QCN9224 radios (2.4, 5 and 6 GHz) and a QCN9074 scan radio
on PCIe, two RJ-45 ports with Realtek RTL8261N 10G PHYs (802.3bt PoE in on
lan1), 32 MiB SPI NOR, 8 GB eMMC, 3 GiB RAM, a TPM 2.0, a PCF85363 RTC, a
Silicon Labs EFR32MG24 for Bluetooth LE, a Quectel LC79H GNSS receiver and a
USB 2.0 port. Installing in [INSTALL.md](INSTALL.md) (a draft: not yet run).
Main track only (`main/build-main.sh ipq95xx`, target qualcommbe, Linux
6.18): there is no 25.12 image.

## What works

Seen on one unit, from RAM (2026-11-10/11), unless marked otherwise.

- **Booting** our unsigned image with U-Boot's `bootm` (Secure Boot is on;
  Arista's own boot command checks signatures, `bootm` does not).
- **Three QCN9224 radios** (ath12k): access points on 2.4, 5 and 6 GHz with
  Arista's board data and regulatory table (`ipq-wifi-arista_c-460`) and
  firmware WLAN.WBE.1.4.1-00199 (`arista-c460-wifi-firmware`; OpenWrt's
  WBE.1.6 crashes after WMI init on these single-MAC cards).
- **The QCN9074 scan radio** (ath11k) with firmware WLAN.HK.2.5.0.1-01208
  (every later public build stops answering at its first interface): scans
  on 2.4, 5 and 6 GHz, receives in monitor mode. Its interface is off by
  default, and with no interface up it leaves the regulatory domain to
  the access-point radios (0111/0116).
- **Ethernet.** lan1 at 10 Gb/s with the MAC from ART, in `br-lan` with DHCP.
- **eMMC and NOR** (NOR read-only but for the U-Boot environment, which
  `fw_printenv` reads).
- **RTC** (PCF85363), **TPM 2.0**, **Bluetooth LE** (`hci0`), **USB 2.0**
  (as Arista specifies the port).
- **GNSS** (Quectel LC79H on I2C, 0130): its NMEA through gpsd on
  localhost:2947. Satellites and time need a view of the sky.
- **LEDs**: the port and radio LEDs follow link and radio state; checked by
  eye: not yet.

## Not yet

The install onto eMMC, the reset button, the LED eye check, lan2 with a
cable, and multi-link (MLO).
