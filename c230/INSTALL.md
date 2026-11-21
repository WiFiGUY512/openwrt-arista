# OpenWrt on the Arista C-230: installing

**Install it with the network installer:
[openwrt-arista-installer/install](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/install/README.md).**
One command on a PC on the AP's network, no console cable.
It finds the AP, saves the AP's own firmware to the PC, installs the current
build, and can put Arista's firmware back later. That page has the command,
what you will see, and what to do if it stops.

The rest of this page is what is particular to the C-230 once it is
installed.

## After the install

* **Arista's system in slot 1 is kept.** OpenWrt goes into NAND slot 0, and
  slot 1 is the fallback. A C-230 may have been running Arista from slot 0:
  that copy and its settings are replaced, and they are in the backup the
  installer saved to the PC.
* **Find the AP in your DHCP server's leases.** The installer prints the
  address when it is done.
* **Cable one Ethernet port.** lan1 and lan2 are both in `br-lan`: cable one
  of them, or turn on STP. Two on the same switch make a loop.
* **Wi-Fi is off** until you turn it on, and there is no root password yet:
  set one first. LuCI is at `http://<AP address>`.
* **Updates** are ordinary `sysupgrade`s with `...-squashfs-sysupgrade.bin`,
  which keep the settings (and the Bluetooth PS keys file); or run the
  installer again and choose "Update OpenWrt".

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console-cable procedure. Most installs never
need it.
