# OpenWrt on the Arista W-118: installing

**Install it with the network installer:
[openwrt-arista-installer/install](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/install/README.md).**
One command on a PC on the AP's network: no console cable, and the case stays
closed. It finds the AP, saves the AP's own firmware to the PC, installs the
current build, and can switch the AP back to Arista's firmware later. That
page has the command, what you will see, and what to do if it stops.

The rest of this page is what is particular to the W-118 once it is
installed.

## After the install

* **Arista's system is kept in full.** OpenWrt goes into the half of the
  NAND that Arista's system leaves unused (`ubi`, the upper 128 MiB). Both of
  Arista's slots stay, nothing of Arista's is written, and Arista's own boot
  is the fallback.
* **Find the AP in your DHCP server's leases.** It takes its address by DHCP
  on the uplink. The installer prints the address when it is done.
* **Wi-Fi is off** until you turn it on, and root logs in without a
  password: set one first.
* **Updates** are ordinary `sysupgrade`s with `...-squashfs-sysupgrade.bin`,
  which keep the settings; or run the installer again and choose "Update
  OpenWrt".
* **Switching back to Arista** with the installer changes the boot setting
  only: Arista's system boots as before, from the slot its `pri` names.
  OpenWrt's volumes stay in `ubi` until something else is written there.

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console procedure. The W-118's console is a
header inside the case. Most installs never need it.
