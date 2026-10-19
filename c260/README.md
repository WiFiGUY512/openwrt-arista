# Arista C-260

A Wi-Fi 6 campus access point: a Qualcomm IPQ8078A with its own 2.4 and
5 GHz radios, a QCA9882 third radio (Arista's scan radio), two 5 GbE ports
with PoE in, a CSR8811 Bluetooth controller and a USB 2.0 port. Details in
[HARDWARE.md](HARDWARE.md); installing in [INSTALL.md](INSTALL.md).

## What works

Seen working on a unit unless marked otherwise.

- **Installing and updating.** OpenWrt in NAND slot 0, booted by its own
  U-Boot `bootcmd`, with Arista's system in slot 1 as the fallback. Booting by
  itself, `sysupgrade` keeping settings, and the fallback booting Arista, all
  on a unit.
- **All three radios.** radio1 (5 GHz) and radio2 (2.4 GHz) are the
  IPQ8074's (ath11k), with the unit's calibration from ART and Arista's board
  data for the wireless country, copied from slot 1: they serve clients. A
  fresh install has no country yet and takes Arista's default board data;
  once a country is set, the file for it is copied in, and the radios use it
  from the next reboot. radio0 is the QCA988x (ath10k-ct, 2.4/5 GHz), calibration
  from ART: the scan radio, as on Arista's system. On a unit: access points
  on all three (the QCA988x at VHT80, with airscan off).
- **The scan radio** (`airscan`, the C-360's): the serving radios never stop
  to scan; the QCA988x does all of it, receive only. airscan takes radio0 out
  of netifd and runs, one at a time: spectral sweeps (2.4 and 5 GHz, 20 MHz
  windows, busy time per channel), passive scans of every channel, and a
  monitor-mode survey of the clients on the channels with networks, which
  finds wired rogues and evil twins (the wired-probe method) and deauth
  floods. Results on ubus (`airscan`), in /tmp/airscan and in LuCI. It also
  runs the Bluetooth LE survey. Another service can borrow the radio
  (`ubus call airscan lend`), as a client test does. On a unit: 29 networks,
  51 clients, all 32 spectral windows (ath10k takes 255 samples a trigger, so
  each window is nine bursts, eight of 255 and one of 8; a 5 GHz sweep takes
  about a minute).
  That holds while airscan has the radio: it marks it (`airscan '1'` in
  radio0's section), and what keeps the serving radios off scanning (Aeolus)
  reads the mark. Turned off, airscan takes the mark away and the AP is like
  any OpenWrt AP: its serving radios scan when asked to (LuCI's Scan, a
  channel on auto when the Wi-Fi starts). While airscan has it, radio0 has
  no `country` of its own (OpenWrt gives a disabled radio's country to the
  whole AP, so one unlike the serving radios' switches it at every boot, as
  on the C-360); the serving radios set it, and turned off, airscan gives
  radio0 theirs.
  To serve clients on it instead: `uci set airscan.main.enabled=0`,
  `uci set wireless.radio0.disabled=0`, commit both, and restart airscan and
  then the Wi-Fi (on a unit: the mark gone with airscan off, and back with
  it on again).
- **Ethernet: two 5 GbE ports** (Aquantia AQR114C), both PoE in. eth0 is
  Ethernet 1 and eth1 Ethernet 2. MACs from ART: eth0 has Arista's base MAC,
  the label MAC, and eth1 the one below it.
  - On a unit, each at 5 Gb/s and at 2.5 Gb/s, and Ethernet 2 at 1 Gb/s too.
    Ethernet 2 on its own (out of `br-lan`, its own DHCP client): an address
    from its own MAC, and traffic both ways.
  - Traffic to and from the AP itself (iperf3, four streams, to a server on
    10G): about 2.4 Gb/s each way. One core takes all of a port's receive
    work; with receive packet steering on all four cores, 3.31 Gb/s sent,
    and received still near 2.3 Gb/s, as the Ethernet driver's receive
    interrupt is on one core. What it forwards between Wi-Fi and Ethernet is
    not yet measured at these speeds.
  - It runs on either port's power: on a unit on 802.3bt on both, Ethernet 1
    pulled, it stayed up on Ethernet 2's, without a restart. A switch powers
    either as a class 5 device.
- **Ethernet 1 is the uplink; there is no WAN.** On a fresh install `br-lan`
  holds Ethernet 1 only and takes its address by DHCP, so the port works as an
  access port, and as a trunk once VLANs are added on it. Ethernet 2 is free,
  in no bridge, so two cables to one switch make no loop. As on the C-360.
- **Ethernet 2, or a bond, with `arista-c260-net`** (the C-360's
  `arista-c360-net`, the same script under the C-260's name):

  | command | what it does |
  |---|---|
  | `port2 lan` | Ethernet 2 on the LAN, with Ethernet 1 |
  | `port2 vlan 30` | Ethernet 2 an access port on VLAN 30, bridged to VLAN 30 on the uplink |
  | `port2 trunk 20 30` | the LAN untagged and VLANs 20 and 30 tagged, to chain another AP |
  | `port2 vxlan 100 <peer>` | Ethernet 2 bridged into a VXLAN tunnel (VNI 100) |
  | `port2 off` | Ethernet 2 back in no bridge |
  | `bond on` / `bond off` | both ports one LACP bond (802.3ad), and back; the uplink's VLANs move with it |
  | `status` | the uplink, the bridges and their ports |

  - A device on Ethernet 2 needs power of its own: both ports are PoE in only.
  - Each change is undone after 120 s unless `arista-c260-net confirm` follows,
    so a change that cuts the AP off reverts by itself.
  - On a LAN bridge that filters VLANs (bridge-vlan sections, as a manager
    sets it up), the VLANs are `br-lan`'s VLAN table: `port2 lan` puts
    Ethernet 2 untagged in the uplink's untagged VLAN, `vlan` and `trunk` add
    it to the table (a VLAN the table lacks is added, tagged on the uplink),
    and `bond on` moves the table's entries to the bond. Tested on main on a
    managed unit: each mode on a copy of its config, and `port2 vlan 20`
    applied and taken off again.
  - The tool notes when Ethernet 2 joins a bridge with no spanning tree (a
    stock install's): cabled to the uplink's switch, that would be a loop.
  - Bonding (`kmod-bonding`) and netifd's `vxlan` are in the image for it.
  - On main, against an Arista switch with LACP fallback: Ethernet 2 at
    2.5G, 2.35 Gb/s each way (iperf3); `bond on`, both ports in one
    aggregator with the switch.
- **Bluetooth** (`arista-c260-bluetooth`): the CSR8811 starts as Arista
  starts it, with its PS keys copied from slot 1, and is `hci0` for BlueZ
  (HCI 4.2), powered on with LE on, not advertising, as the C-360's is. On a
  unit: airscan's LE survey heard 17 devices in 6 s.
- **The LEDs.** Power is orange while booting, in failsafe and while
  upgrading, green when running. Each Ethernet port's LED is green for a 2.5
  or 5 Gb/s link and orange for 1 Gb/s or slower (seen on a unit: green at
  2.5 and 5 Gb/s, orange at 1 Gb/s). Each radio's
  green LED (2.4 GHz, 5 GHz, scanning radio) is lit while the radio is on;
  the orange ones are left off.
- **The button** (gpio52), as OpenWrt's reset: a short press reboots, 5 s or
  more resets the settings (OpenWrt's own handler; on a unit, the presses
  and releases were seen).
- **USB:** one USB 2.0 port, working at its full 480 Mb/s. To use it for
  storage, add `kmod-usb-storage` (from this build's feed) and
  `block-mount`.
- **The console** on its RJ-45 port, 115200 8N1.
- **Arista's PoE power policy** (`arista-c260-power`): on 802.3at (or af)
  power with no DC supply, the serving radios' transmit power
  is capped (23 dBm at 2.4 GHz, 25 dBm at 5 GHz: Arista's 23.5 and 25.5,
  in whole dBm) and the Bluetooth controller turned off, as Arista's own
  system does. Its USB and antenna chains stay as they are, as on Arista's;
  the scan radio is left alone. The PoE class is the better of the two
  ports', each from the PoE controller's pins (HARDWARE.md) or the power a
  switch allocates on it by LLDP. Arista's system reads only Ethernet 1's,
  which reads as 802.3af with nothing on it, and so would cap a C-260 that
  runs on Ethernet 2's 802.3bt. While the power is reduced the power LED
  is orange, green at full power (option `led`, as on the C-360).
  `arista-c260-power status` shows what it
  reads and what is applied;
  `/etc/config/arista-c260-power` turns it off or changes the caps. Tested
  on a unit on 802.3bt (full power), and the 802.3at path with a test
  override: caps applied and lifted, Bluetooth off and back.

## What doesn't (yet)

- Nothing known not to work. Not yet measured: what it forwards at over
  2.5 Gb/s (Ethernet, above).

## In this directory

```
README.md, INSTALL.md, HARDWARE.md
model.sh, openwrt.lock, config/      for ../build.sh
patches/openwrt/                     the device, calibration, sysupgrade,
                                     LEDs, network roles, fw_setenv
files/                               the device tree, the board-data and
                                     radio-LED hotplugs, the board data's
                                     country refresh, the
                                     arista-c260-bluetooth,
                                     arista-c260-power and airscan
                                     (with luci-app-airscan) packages, and
                                     the Ethernet driver's fix (qca-nss-dp);
                                     airscan and the fix are the C-360's,
                                     kept the same
feeds/packages/                      the C-360's BlueZ fix (btmgmt)
```
