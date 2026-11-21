# OpenWrt on the Arista W-318: installing

**Install it with the network installer:
[openwrt-arista-installer/install](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/install/README.md).**
One command on a PC on the AP's network, no console cable. It finds the AP,
saves the AP's own firmware to the PC, installs the current build, and can
switch the AP back to Arista's firmware later. That page has the command,
what you will see, and what to do if it stops.

The rest of this page is what is particular to the W-318 once it is
installed.

## After the install

* **Arista's system in slot 1 is kept, and must stay.** OpenWrt takes
  Arista's slot 0: its kernel in NOR `0:HLOS`, its root in the eMMC partition
  `rootfs`, its settings in `rootfs_data`. Slot 1 is the fallback, and it is
  where OpenWrt gets the 6 GHz card's firmware and the radios' board data
  from.
* **Find the AP in your DHCP server's leases.** It takes its address by DHCP
  on the uplink. The installer prints the address when it is done.
* **Cable the uplink only.** The builds the installer puts on have the
  uplink and Network 1, 2 and 3 all in `br-lan`, so a LAN port cabled to the
  uplink's switch makes a loop. `arista-w318-net lan<n> off` frees one
  ([README.md](README.md)).
* **Wi-Fi is off** until you turn it on, and there is no root password yet:
  set one first.
* **Set the Wi-Fi country, then reboot once.** The radios take Arista's
  FCC_CE board data (the US and the EU) until a country is set; then the
  country's group's, from the radios' next start.
* **Failsafe mode** is at 192.168.1.1, as on any OpenWrt device: press `f`
  and Enter on the console when the boot offers it.
* **Updates** are ordinary `sysupgrade`s with a newer
  `squashfs-sysupgrade.bin` (LuCI or the command line), which keep the
  settings unless told not to; or run the installer again and choose "Update
  OpenWrt". Slot 1 is never touched.
* **Switching back to Arista** with the installer changes the boot setting
  only: the AP starts the copy of Arista's firmware in slot 1. That copy
  keeps its own settings; if it refuses `config` / `config`, press the AP's
  reset button once it has finished starting.

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console-cable procedure. Most installs never
need it.
