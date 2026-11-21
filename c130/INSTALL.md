# OpenWrt on the Arista C-130: installing

**Install it with the network installer:
[openwrt-arista-installer/install](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/install/README.md).**
One command on a PC on the AP's network, no console cable. It finds the AP,
saves the AP's own firmware to the PC, installs the current build, and can
switch the AP back to Arista's firmware later. That page has the command,
what you will see, and what to do if it stops.

The rest of this page is what is particular to the C-130 once it is
installed.

## After the install

* **Arista's system in slot 1 is kept.** OpenWrt goes into NAND slot 0
  (Arista's `rootfs` and `opt`, 64 MiB together), and slot 1 (`rootfs2`,
  `opt2`) with its kernel in NOR is the fallback. A C-130 runs Arista from
  slot 0: that copy and its settings are replaced, and they are in the backup
  the installer saved to the PC.
* **Power it from 802.3at or 12 V DC.** OpenWrt has no 802.3af power policy
  on the C-130 yet: all three radios run at full power on any source.
* **Find the AP in your DHCP server's leases.** It takes its address by DHCP
  on the PoE+ port; the installer prints the address when it is done.
  OpenWrt's DHCP client releases its lease when it shuts down, so a DHCP
  server may hand out another address on each boot: reserve one for the
  unit's MAC (the label MAC) or its client ID.
* **Wi-Fi is off** until you turn it on, and there is no root password yet:
  set one first.
* **Updates** are ordinary `sysupgrade`s with
  `openwrt-ipq806x-generic-mojo_c-130-squashfs-sysupgrade.bin`, which keep
  the settings; or run the installer again and choose "Update OpenWrt".
* **Switching back to Arista** with the installer changes the boot setting
  only: the AP starts the copy of Arista's firmware in slot 1. That copy keeps
  its own settings; if it refuses `config` / `config`, press the AP's reset
  button once it has finished starting.

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console-cable procedure. Most installs never
need it.
