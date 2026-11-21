# OpenWrt on the Arista C-360: installing

**Install it with the network installer:
[openwrt-arista-installer/install](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/install/README.md).**
One command on a PC on the AP's network, no console cable.
It finds the AP, saves the AP's own firmware to the PC, installs the current
build, and can put Arista's firmware back later. That page has the command,
what you will see, and what to do if it stops.

The rest of this page is what is particular to the C-360 once it is
installed.

## After the install

* **Arista's system in slot 1 is kept, and must stay.** OpenWrt goes into
  NAND slot 0. Slot 1 is the fallback, and it is where OpenWrt gets the
  radios' firmware and board data from: if slot 1 is erased, none of the
  radios start.
* **Find the AP in your DHCP server's leases.** It uses the unit's own MAC,
  the one on its label. The installer prints the address when it is done.
* **Cable one Ethernet port.** The builds the installer puts on have both
  ports in `br-lan`, so two cables to the same switch make a loop.
  `arista-c360-net port2 off` frees Ethernet 2; the same tool puts it on a
  VLAN or a VXLAN, or bonds both ports ([README.md](README.md)).
* **Wi-Fi is off** until you turn it on, and SSH and LuCI have no password:
  set one first.
* **Set the Wi-Fi country, then reboot once.** The board data is chosen by
  the wireless country's group, and a fresh install has no country yet, so it
  starts with FCC_CE's. When the country is set, its group's files are copied
  in; the radios read them from the next boot.
* **Failsafe mode** is at 192.168.1.1, as on any OpenWrt device. Enter it
  from the serial console: press `f` and Enter when the boot offers it.
* **The reset pinhole:** a short press reboots. As on any OpenWrt device, a
  press of 5 s or more resets the configuration.
* **Updates** are ordinary `sysupgrade`s, which keep the settings; or run the
  installer again and choose "Update OpenWrt".

On the first boot, and the first after each `sysupgrade`, the radios take the
Wi-Fi firmware and board data from the Arista slot as they start. If that
fails, `logread` shows `ath11k-vendor-firmware` or `arista-c360-board-data`.

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console-cable procedure. Most installs never
need it.
