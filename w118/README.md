# Arista W-118

A Wi-Fi 5 wall-plate access point (formerly Mojo W-118): a Qualcomm IPQ4019
with its own 2.4 and 5 GHz radios, a QCA9882 scanning radio on PCIe, a 1 GbE
uplink with PoE in, three 1 GbE LAN ports (LAN 3 also a PoE output) and an
NXP Bluetooth LE controller. No USB, no TPM. Details in
[HARDWARE.md](HARDWARE.md); installing in [INSTALL.md](INSTALL.md).

OpenWrt main only: `main/build-main.sh ipq40xx` (`../main/README.md`). There
is no 25.12 image. Upstream: openwrt/openwrt#26028 (the device, as `main`'s
patches 0014-0017 carry it), #26027 (the ipq40xx console login, which took
the Bluetooth UART) and openwrt/firmware_qca-wireless#179 (board data).

## What works

Seen working on a unit unless marked otherwise.

- **Installing and updating.** OpenWrt in the NAND's upper half (`ubi`),
  booted by its own U-Boot boot command first, with Arista's boot as the
  fallback; both of Arista's slots kept (INSTALL.md). On a unit: the install
  as INSTALL.md has it (TFTP initramfs, `sysupgrade -n`), boots by itself,
  `sysupgrade` keeping the settings, and the boot command's fallback path
  (with the kernel volume missing, OpenWrt's part fails and Arista's boot
  would run).
- **All three radios** (ath10k-ct): the IPQ4019's 2.4 and 5 GHz radios with
  Arista's own board data (`ipq-wifi-arista_w-118`) and calibration from
  ART; the QCA9882 with its calibration from ART. On a unit: access points
  on all three (SAE): 2.4 GHz, 5 GHz VHT80, and the QCA9882 on 5 GHz VHT80.
- **The scanning radio**: airscan on the QCA9882 (PCI 0000:01:00.0), as on
  the C-260, which has the same card: spectral, BSS and client surveys, and
  the Bluetooth survey (`ubus call airscan …`, LuCI's airscan pages).
  *Not yet run on a unit.*
- **Ethernet.** The uplink (WAN on the panel) and LAN 1-3 are `uplink`,
  `lan1`, `lan2` and `lan3`, all in `br-lan` by default (as upstream has
  it), which takes its address by DHCP. MACs from ART: the uplink has the
  label MAC, the LAN ports the next lower one.
- **Bluetooth** (`/etc/init.d/arista-w118-ble`): bluetooth-uart attaches the
  NXP controller (ttyMSM1, 115200, no flow control) as `hci0`; at boot the
  script resets it on GPIO 42 as Arista does, waits for its bootloader,
  attaches it again and powers it on, not advertising, with its public
  address. On a unit: 748 advertisements from 15 devices in 10 s.
- **The LEDs.** Power is green when running. The uplink's is green while it
  has a link, at any speed. Each radio's LED is lit while the radio is on.
  "Network 1/2/3" is one LED for the three LAN ports: green while any of
  them has a link (`arista-w118-lanled`).
- **The reset button**, as OpenWrt's reset (presses seen on a unit).
- **PoE out on LAN 3**: off by default; `echo 1 >
  /sys/class/gpio/pse-enable/value` turns it on. On a unit: a C-360 on LAN 3
  powered up and linked, also with the W-118 on 12 V DC.
- **fw_printenv / fw_setenv** on `0:appsblenv`.

## What doesn't (yet)

- **No spanning tree on `br-lan`**, which bridges all four ports: two of
  them cabled to the same switch make a loop. Cable one, or turn on STP.
- **No PoE power policy**: what Arista's system does on 802.3af power is
  not yet read.
- **airscan** on the W-118 has not yet run on a unit.
- The pass-through jacks are wired to each other, not to the AP: nothing for
  OpenWrt to do there.

## In this directory

```
README.md, INSTALL.md, HARDWARE.md
files/      the Bluetooth reset and power-on, the Network 1/2/3 LED
```

The device itself is in `../main/patches/openwrt/` (0014-0017), its board
data in `../main/openwrt.lock` (the qca-wireless picks).
