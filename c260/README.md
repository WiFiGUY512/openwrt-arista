# Arista C-260

A Wi-Fi 6 campus access point: a Qualcomm IPQ8078A with its own 2.4 and
5 GHz radios, a QCA988x third radio (Arista's scan radio), two 5 GbE ports
with PoE in, a CSR8811 Bluetooth controller and a USB 3.0 port. Details in
[HARDWARE.md](HARDWARE.md); installing in [INSTALL.md](INSTALL.md).

## What works

Seen working on a unit unless marked otherwise.

- **Installing and updating.** OpenWrt in NAND slot 0, booted by its own
  U-Boot `bootcmd`, with Arista's system in slot 1 as the fallback. Booting by
  itself and `sysupgrade` keeping settings, both on a unit.
- **All three radios.** radio0 is the QCA988x (ath10k-ct, 2.4/5 GHz),
  calibration from ART; radio1 (5 GHz) and radio2 (2.4 GHz) are the
  IPQ8074's (ath11k), with the unit's calibration from ART and Arista's board
  data for the configured country, copied from slot 1 the first time. On a
  unit: access points on all three (the QCA988x at VHT80), and scans.
- **Ethernet: two 5 GbE ports** (Aquantia AQR114C). eth0 is the first port
  (linked at 2.5 Gb/s on a unit), eth1 the second. Both are in `br-lan`, which
  takes its address by DHCP; there is no WAN. MACs from ART: eth0 has
  Arista's base MAC, the label MAC.
- **Bluetooth** (`arista-c260-bluetooth`): the CSR8811 starts as Arista
  starts it, with its PS keys copied from slot 1, and is `hci0` for BlueZ
  (HCI 4.2, LE scanning seen on a unit).
- **The console** on its RJ-45 port, 115200 8N1.

## What doesn't (yet)

- **LED names and colours:** the twelve LED outputs are there
  (`c260:out0`…`c260:out13`), but which is which on the front is not yet
  looked at, so OpenWrt does not drive them yet.
- **Not yet tried on a unit:** the button (gpio52, as reset), a USB device,
  a real boot into Arista's fallback, and 5 Gb/s links.
- **PoE power classes:** Arista turns things down on 802.3af/at; OpenWrt
  does not.

## In this directory

```
README.md, INSTALL.md, HARDWARE.md
model.sh, openwrt.lock, config/      for ../build.sh
patches/openwrt/                     the device, calibration, sysupgrade,
                                     network roles, fw_setenv
files/                               the device tree, the board-data hotplug,
                                     and the arista-c260-bluetooth package
```
