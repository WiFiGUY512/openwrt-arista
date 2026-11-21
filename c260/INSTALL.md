# OpenWrt on the Arista C-260: installing

**Install it with the network installer:
[openwrt-arista-installer/install](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/install/README.md).**
One command on a PC on the AP's network, no console cable.
It finds the AP, saves the AP's own firmware to the PC, installs the current
build, and can put Arista's firmware back later. That page has the command,
what you will see, and what to do if it stops.

The rest of this page is what is particular to the C-260 once it is
installed.

## After the install

* **Arista's system in slot 1 is kept, and must stay.** OpenWrt goes into
  NAND slot 0. Slot 1 is the fallback, and it is where OpenWrt gets the
  IPQ8074 radios' board data and the Bluetooth controller's PS keys from.
* **Find the AP in your DHCP server's leases.** It uses the unit's base MAC,
  the one on its label. The installer prints the address when it is done.
* **Cable one Ethernet port.** The builds the installer puts on have both
  ports in `br-lan`, so two cables to the same switch make a loop.
  `arista-c260-net port2 off` frees Ethernet 2; the same tool puts it on a
  VLAN or a VXLAN, or bonds both ports ([README.md](README.md)).
* **Wi-Fi is off** until you turn it on, and SSH and LuCI have no password:
  set one first.
* **Set the Wi-Fi country, then reboot once.** The board data is chosen by
  the wireless country, and a fresh install has none yet, so it starts with
  Arista's default. When the country is set, the file for it is copied in;
  the radio reads it from the next boot.
* **Failsafe mode** is at 192.168.1.1, as on any OpenWrt device: press `f`
  and Enter on the console when the boot offers it.
* **Updates** are ordinary `sysupgrade`s, which keep the settings; or run the
  installer again and choose "Update OpenWrt".

On the first boot, and the first after each `sysupgrade`, the IPQ8074 radio
takes its board data from the Arista slot as it starts, and the Bluetooth
controller its PS keys. `logread` shows `arista-c260-board-data` and
`arista-c260-bluetooth`.

## If the installer cannot reach the AP

[BY-HAND.md](BY-HAND.md) is the console-cable procedure. Most installs never
need it.
