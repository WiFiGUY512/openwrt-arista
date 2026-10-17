# Arista W-318

A Wi-Fi 6E wall-plate access point: a Qualcomm IPQ6010 with its own 2.4 and
5 GHz radios, a QCN9072 6 GHz card on PCIe, a 2.5 GbE uplink with PoE in,
three 1 GbE LAN ports (Network 1 also a PoE output), an nRF52833 Bluetooth LE
module, a TPM and a USB 3.0 port. No scan radio. Details in
[HARDWARE.md](HARDWARE.md); booting it in [INSTALL.md](INSTALL.md).

**Status: in progress.** Everything below runs on a unit **booted from
RAM**; OpenWrt is not installed to its flash yet (the install is designed,
in HARDWARE.md, but not built or run).

## What works

Seen working on a unit, from RAM, unless marked otherwise.

- **All three radios.** radio1 (2.4 GHz) and radio0 (5 GHz) are the
  IPQ6010's (ath11k, OpenWrt's own IPQ6018 firmware), radio2 (6 GHz) the
  QCN9072 card (ath11k's QCN9074, Gen 3 x1). Calibration from the unit's ART
  (it carries the radios' MACs), board data for the wireless country from
  Arista's system in eMMC slot 1. The card starts only with Arista's build of
  its firmware (WLAN.HK.2.5.r4, as on the C-360), copied from slot 1 when it
  is first asked for. On a unit: access points on all three bands (WPA3),
  heard by another AP; a client on 6 GHz at HE80 MCS 9 (480 Mb/s) and on
  5 GHz.
- **Ethernet.** The uplink (2.5 GbE, QCA8081) and Network 1, 2 and 3 (1 GbE,
  QCA8075) are `uplink`, `lan1`, `lan2` and `lan3`. The uplink is the LAN
  (`br-lan`), which takes its address by DHCP; there is no WAN. Network 1-3
  stay in no bridge, so a LAN port cabled to the uplink's switch makes no
  loop; to use them, add them to `br-lan` (or a VLAN of their own) in LuCI or
  `/etc/config/network`. MACs from ART: the uplink has Arista's base MAC, the
  label MAC. On a unit: the uplink at 2.5 Gb/s, each LAN port at 1 Gb/s (in
  `br-lan`).
- **Bluetooth** (`/etc/init.d/arista-w318-ble`): the nRF52833 runs Arista's
  Zephyr HCI firmware; it is `hci0` for BlueZ, powered on with LE, a static
  address from ART, not advertising. On a unit: 14 devices heard in 10 s.
- **The TPM:** TPM 2.0 on SPI (`/dev/tpm0`, `/dev/tpmrm0`).
- **USB 3.0:** a stick at 5 Gb/s, 197 MB/s read.
- **The LEDs.** Power is amber while booting, in failsafe and while
  upgrading, green when running. The uplink's is green for a 2.5 Gb/s link
  and orange for 1 Gb/s or slower. Each radio's green LED is lit while the
  radio is on. Network 1/2/3 share one LED: green with a 1 Gb/s link on any
  of them, amber with slower ones only, off with none
  (`arista-w318-lanled`); a port in no bridge stays down, and dark.
- **The button**, the one outside, as OpenWrt's reset: a short press reboots,
  5 s or more resets the settings (presses and releases seen on a unit).
- **Arista's PoE power policy** (`arista-w318-power`): on 802.3at (or af)
  power without a DC supply, the USB port's power is cut and the radios'
  transmit power capped (18 dBm at 2.4 GHz, 17 dBm at 5 and 6 GHz), as
  Arista's own system does; Bluetooth and the chains stay. Network 1's PoE
  output is on only when the W-318 itself runs on 802.3bt (as the datasheet
  has it: off on 802.3at and on a DC supply). The PoE class comes from the
  PoE controller's pins, or from the power a switch allocates by LLDP.
  `arista-w318-power status` shows what it reads and what is applied;
  `/etc/config/arista-w318-power` turns it off, turns the PoE output off or
  changes the caps. On a unit on 802.3bt: full power, the PoE output's
  enable set; the 802.3at path with a test override: the USB stick gone and
  back, caps applied. A device powered from Network 1 not yet tried.
- **The console** on its RJ-45 port, 115200 8N1.

## What doesn't (yet)

- **Installing.** Only the RAM boot (INSTALL.md).
- **No spanning tree** on `br-lan`: a LAN port added to it and cabled to the
  uplink's switch makes a loop (seen on a lab switch, whose spanning tree
  blocked the uplink).
- The pass-through jacks (rear and right side) are wired to each other, not
  to the AP: nothing for OpenWrt to do there.

## In this directory

```
README.md, INSTALL.md, HARDWARE.md
model.sh, openwrt.lock, config/      for ../build.sh
patches/openwrt/                     the device, calibration, kmod-tpm-tis
files/                               the device tree, the radio firmware and
                                     board-data hotplugs, the board data's
                                     country refresh, the radio-LED hotplug,
                                     the Bluetooth bring-up, the Network LED,
                                     the arista-w318-power package, and the
                                     Ethernet driver's fix (qca-nss-dp, the
                                     C-360's, kept the same)
feeds/packages/                      the C-360's BlueZ fix (btmgmt)
```
