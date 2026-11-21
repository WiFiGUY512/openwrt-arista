# OpenWrt on the Arista C-460: installing

**Install it with the network installer:
[openwrt-arista-images/install](https://github.com/WiFiGUY512/openwrt-arista-images/blob/main/install/README.md).**
One command on a PC on the AP's network, no console cable. It finds the AP,
saves the AP's own firmware to the PC, installs the current build, and can
put Arista's firmware back later. That page has the command, what you will
see, and what to do if it stops.

No published build carries the C-460 yet. Until one does, the installer
recognises the AP, can save its firmware, and says there is nothing to
install.

The rest of this page is what is particular to the C-460 once it is
installed.

## After the install

* **Arista's system in slot 1 is kept.** OpenWrt goes into slot 0 of the
  eMMC (`0:HLOS` for the kernel, `rootfs` for the root file system), and
  slot 1 (`0:HLOS_1`, `rootfs_1`) is the fallback.
* **A C-460 runs Arista from slot 0,** so the install replaces the system
  that was running; it is in the backup the installer saved to the PC. When
  the installer puts Arista's firmware back, Arista starts from its factory
  defaults: its settings partition cannot be restored.
* **Find the AP in your DHCP server's leases.** It takes its address by DHCP
  on lan1, the PoE port. The installer prints the address when it is done.
* **Wi-Fi is off** until you turn it on, and there is no root password yet:
  set one first.
* **Updates** are ordinary `sysupgrade`s with `...-squashfs-sysupgrade.bin`,
  which keep the settings; or run the installer again and choose "Update
  OpenWrt".

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console-cable procedure. Most installs never
need it.
