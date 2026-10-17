# OpenWrt on the Arista W-318 — booting it

Status: OpenWrt is not installed to the W-318's flash yet. What follows boots
this repo's initramfs from RAM, which writes nothing: a power cycle brings
Arista's system back. The install (HARDWARE.md, "Installing") comes later.

## What you need

* The console: the RJ-45 console port, 115200 8N1, no flow control.
* A TFTP server on the W-318's network with
  `openwrt-qualcommax-ipq60xx-arista_w318-initramfs-uImage.itb` from
  `out/w318/<version>/`.
* The uplink port cabled to that network (it takes PoE).

## 1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot (the C-360's and C-260's too):

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Paste it repeatedly while the W-318 powers up until you see `IPQ6018#`, then
press Ctrl-C once to clear what is left on the line. Stop it before Arista's
boot runs: that boot saves the U-Boot environment each time.

## 2. Load and boot OpenWrt from RAM

Set the network for this boot only (`setenv` without `saveenv` writes
nothing), with addresses for your network:

```
setenv ipaddr 192.168.1.76
setenv netmask 255.255.255.0
setenv serverip 192.168.1.10
setenv bootargs console=ttyMSM0,115200n8 rootwait
tftpboot 0x60000000 openwrt-qualcommax-ipq60xx-arista_w318-initramfs-uImage.itb
bootm 0x60000000#config@cp01-c3
```

Don't `saveenv`.

## 3. Use it

OpenWrt takes an address by DHCP on the uplink (`br-lan`; the three LAN ports
are in no bridge until you add them); find it on the console (`ip -4 addr show br-lan`) or in your DHCP
server's leases. SSH as root, no password; LuCI on port 80. Wi-Fi starts
off, as OpenWrt's default. The radios take Arista's FCC_CE board data (the
US and the EU) at their first start; another country's comes at their next
start, which on a RAM boot means a reboot that ends it.

Arista's system stays on the flash, untouched. To go back to it, power cycle
the W-318 (or `reboot` and let U-Boot run).
