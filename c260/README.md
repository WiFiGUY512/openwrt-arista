# Arista C-260

A Wi-Fi 6 campus access point: a Qualcomm IPQ8078A with its own 2.4 and
5 GHz radios, a QCA988x third radio (Arista's scan radio), two 5 GbE ports
with PoE in, a CSR8811 Bluetooth controller and a USB 3.0 port. Details in
[HARDWARE.md](HARDWARE.md); installing in [INSTALL.md](INSTALL.md).

## What works

Seen working on a unit unless marked otherwise.

- **Installing and updating.** OpenWrt in NAND slot 0, booted by its own
  U-Boot `bootcmd`, with Arista's system in slot 1 as the fallback. Booting by
  itself, `sysupgrade` keeping settings, and the fallback booting Arista, all
  on a unit.
- **All three radios.** radio1 (5 GHz) and radio2 (2.4 GHz) are the
  IPQ8074's (ath11k), with the unit's calibration from ART and Arista's board
  data for the configured country, copied from slot 1 the first time: they
  serve clients. radio0 is the QCA988x (ath10k-ct, 2.4/5 GHz), calibration
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
  each window is eight bursts; a 5 GHz sweep takes about a minute).
  To serve clients on it instead: `uci set airscan.main.enabled=0`,
  `uci set wireless.radio0.disabled=0`, commit both, and restart airscan and
  the Wi-Fi.
- **Ethernet: two 5 GbE ports** (Aquantia AQR114C). eth0 is the first port
  (linked at 2.5 Gb/s on a unit), eth1 the second. Both are in `br-lan`, which
  takes its address by DHCP; there is no WAN. MACs from ART: eth0 has
  Arista's base MAC, the label MAC.
- **Bluetooth** (`arista-c260-bluetooth`): the CSR8811 starts as Arista
  starts it, with its PS keys copied from slot 1, and is `hci0` for BlueZ
  (HCI 4.2), powered on with LE on, not advertising, as the C-360's is. On a
  unit: airscan's LE survey heard 17 devices in 6 s.
- **The LEDs.** Power is orange while booting, in failsafe and while
  upgrading, green when running. Each Ethernet port's LED is green for a 2.5
  or 5 Gb/s link and orange for 1 Gb/s or slower. Each radio's green LED
  (2.4 GHz, 5 GHz, scanning radio) is lit while the radio is on; the orange
  ones are left off.
- **The button** (gpio52), as OpenWrt's reset: a short press reboots, 5 s or
  more resets the settings.
- **USB:** a USB stick is found and mounts (high-speed; SuperSpeed not yet
  seen).
- **The console** on its RJ-45 port, 115200 8N1.

## What doesn't (yet)

- **Not yet tried on a unit:** 5 Gb/s links, and SuperSpeed on the USB port
  (a USB 3.0 stick ran at 480 Mb/s).
- **PoE power classes:** Arista turns things down on 802.3af/at; OpenWrt
  does not.

## In this directory

```
README.md, INSTALL.md, HARDWARE.md
model.sh, openwrt.lock, config/      for ../build.sh
patches/openwrt/                     the device, calibration, sysupgrade,
                                     LEDs, network roles, fw_setenv
files/                               the device tree, the board-data and
                                     radio-LED hotplugs, and the
                                     arista-c260-bluetooth and airscan
                                     (with luci-app-airscan) packages;
                                     airscan is the C-360's, kept the same
```
