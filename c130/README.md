# Arista C-130

A Wi-Fi 5 (802.11ac Wave 2) ceiling access point, formerly the Mojo C-130,
also sold as the WatchGuard AP420: a Qualcomm IPQ8068 (two Krait cores),
512 MiB of RAM, 32 MiB of SPI NOR and 128 MiB of NAND, two 4x4 QCA9994
radios (2.4 and 5 GHz) and a 2x2 QCA9882 scanning radio on a miniPCIe card,
all three on PCIe. Two 1 GbE ports (AR8033 PHYs); the one labelled PoE+
takes 802.3af/at. USB, an RJ-45 console, no Bluetooth, no TPM. Installing:
[INSTALL.md](INSTALL.md).

**The device support is Tomasz Maciej Nowak's** (tmn505, the OpenWrt
ipq806x maintainer): `ipq806x: add Mojo/Arista C-130` from his tree
([tmn505/openwrt](https://github.com/tmn505/openwrt), branch `watchguard`,
commit 4d8dc61995e3), carried here unchanged as main's patch 0134. Its
device tree, image, network and upgrade code and board data are his. It is
not yet in OpenWrt. So the image names say `mojo_c-130` and the board name
is `mojo,c-130`, as his device has them, not `arista_...`.

What this port adds on top: 0135 (the PoE port is the AP's LAN with a DHCP
client, as on the other models; his device makes it a router's WAN), airscan
and dfs-look on the scan card, and the network installer's C-130 path.

OpenWrt main only: `main/build-main.sh ipq806x DIR` (target ipq806x, kernel
6.18, in an OpenWrt directory of its own; `../main/README.md`). There is no
25.12 image.

## What works

Seen working on a unit unless marked otherwise.

- **Installing.** OpenWrt goes into Arista's slot 0 (the first 64 MiB of the
  NAND, Arista's `rootfs` and `opt` partitions, as one UBI), booted by its
  own boot command first, with Arista's boot of slot 1 as the fallback.
  Slot 1 (`rootfs2`, `opt2`) and both kernels in NOR are never written. On a
  unit: the network installer from Arista 13.0.2 (2026-11-16), and the unit
  restarting into it by itself since.
- **All three radios** (ath10k-ct). The 5 GHz QCA9994 (PCIe 0) and the 2.4
  GHz QCA9994 (PCIe 1) at 4x4, with their pre-calibration from ART and
  tmn505's `Mojo-C-130` board data; the QCA9882 card (PCIe 2) at 2x2 on 2.4
  and 5 GHz with its calibration from the card itself. The radios' MAC
  addresses are Arista's own (from ART). On a unit: access points on
  5 GHz (VHT80) and 2.4 GHz.
- **The scanning radio**: airscan on the QCA9882 (PCI 0002:01:00.0), as on
  the C-260 and W-118: spectral sweeps on 2.4 and 5 GHz, the BSS and client
  surveys (`ubus call airscan …`, LuCI's airscan pages). No Bluetooth survey:
  the C-130 has no controller. On a unit: it starts by itself and takes the
  card (the image booted from RAM).
- **dfs-look** on the 5 GHz radio, with airscan's looks. On a unit (`-n`).
- **Ethernet.** The PoE+ port (eth0, the label MAC) is in `br-lan`, which
  takes its address by DHCP; the second port (eth1, the next lower MAC) is in
  no bridge, so a second cable to the same switch makes no loop. Both link at
  1 Gb/s.
- **The LEDs.** The amber power LED shows boot, failsafe and upgrade, and is
  off once the AP is up. Each radio's LED is driven by its radio (ath10k)
  and blinks with its traffic, on the same pins Arista's firmware uses.
- **The reset button** (GPIO 26), as OpenWrt's reset. *Not yet pressed on
  a unit.*
- **USB**: the port's power (GPIO 67) is off by default, as tmn505 left it;
  `echo enabled > /sys/devices/platform/output-usb-vbus/state` turns it on.
  *Not yet run with a device.*
- **fw_printenv / fw_setenv** on `0:appsblenv`.
- **The console**: the RJ-45 port, Cisco pinout, 115200 8N1. U-Boot stops on
  `s6.D5r4Gnb89ZEWSW6Kq.`, and OpenWrt's initramfs starts from RAM by TFTP
  (`BY-HAND.md`).

## What doesn't (yet)

- **The green half of the power LED** blinks with Ethernet traffic: it is the
  PoE port's PHY LED, which Arista's firmware sets steady through the PHY.
- **32 clients per radio** at most: ath10k's default for the QCA9994's
  firmware; Arista specifies 512.
- **The scan card's 5 GHz levels** read 10-18 dB low on channels 36-48
  against the 5 GHz radio, and close elsewhere; which one is right is not yet
  known.
- **No PoE power policy**: on 802.3af Arista's firmware turns USB and the
  second port off and cuts the radios; OpenWrt runs everything at full power.
  Use 802.3at or DC.
- **U-Boot's network after a restart from OpenWrt**: in 2 of 8 restarts on
  the lab unit it passed no traffic until the AP was powered off and on
  (every cold start worked). OpenWrt's own Ethernet is not affected.
- `sysupgrade` from one build to the next, and the installer's switch back
  to Arista, have not yet been run on a unit.

## In this directory

```
README.md, INSTALL.md, BY-HAND.md
```

The device itself is in `../main/patches/openwrt/` (0134-0135); airscan is
in `../c260/files/` and `../c360/files/` (the same package), dfs-look in
`../main/files/`.
