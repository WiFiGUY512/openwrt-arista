# OpenWrt on the Arista C-260 — installation

Status: sections 1–5 were run on one unit on 2026-10-15: the RAM boot,
`ubiformat`, the environment write (the `fw_setenv` of section 5, made from
OpenWrt booted from NAND by hand rather than from the RAM system),
unattended boots from NAND, and `sysupgrade` keeping the settings. On
2026-10-16 sections 1–4 ran again, installing this repo's images afresh (the
environment was already set). The fallback too: from the state a failed
OpenWrt load leaves, `arista_boot` booted Arista's slot 1 with Arista's own
settings; after a power cycle OpenWrt came back by itself, and the U-Boot
environment was as before.

## What you get

* OpenWrt on the IPQ8074 (2.4 + 5 GHz), the QCA9882 third radio and the
  CSR8811 Bluetooth controller.
* OpenWrt lives in NAND slot 0. **Arista's system in slot 1 is kept**: it is
  the fallback, and it is where OpenWrt gets the IPQ8074 board data and the
  Bluetooth controller's PS keys from.
* The image contains no Arista or unit-specific files. When the radio and
  the Bluetooth controller first start, OpenWrt copies those files
  **unmodified from your unit's own Arista slot 1**; MAC addresses and
  calibration come from the unit's ART partition.

## Why it is installed this way

Arista's normal boot (`bootipq`) picks its kernel from SPI NOR by the
BOOTCONFIG partition, and switching that means writing the boot chain's own
partitions. OpenWrt's kernel goes into UBI in NAND slot 0 instead, and its own
U-Boot `bootcmd` loads it from there, falling back to Arista's boot if that
fails. U-Boot, the boot chain, ART and slot 1 are never written.

## You need

* The console cable: RJ-45 rollover (RS-232, not TTL) to the C-260's console
  port, 115200 8N1, no flow control.
* A TFTP server reachable on the AP's untagged network, holding
  `openwrt-qualcommax-ipq807x-arista_c260-initramfs-uImage.itb`.
* `openwrt-qualcommax-ipq807x-arista_c260-squashfs-factory.ubi` on the PC.

## 1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot:

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Paste it repeatedly while the AP boots until you see `IPQ807x#`, then press
Ctrl-C once to clear what is left on the line. **Do not let Arista's
firmware boot by accident while experimenting**: its boot script runs
`saveenv` every time.

## 2. Boot OpenWrt from RAM

At `IPQ807x#` (nothing below is saved):

```
setenv ipaddr <AP address>
setenv serverip <TFTP server>
setenv fdt_high 0x4A3E0000
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat
tftpboot 0x60000000 openwrt-qualcommax-ipq807x-arista_c260-initramfs-uImage.itb
bootm 0x60000000#config@1
```

Add `setenv gatewayip <gateway>` if the TFTP server is on another subnet.
`panic=0` makes a crashing kernel halt instead of rebooting into Arista's
boot, which would save the U-Boot environment.

The RAM system takes an address by DHCP on its LAN, Ethernet 1.

## 3. Back up the flash (strongly recommended)

Only `ubi` (NAND slot 0) and `0:APPSBLENV` are writable. From a PC:

```
for n in $(ssh root@<AP> "cut -d: -f1 /proc/mtd | grep mtd"); do
  ssh root@<AP> "cat /dev/$n" > c260-$n.bin
done
ssh root@<AP> cat /proc/mtd > c260-proc-mtd.txt
```

Check hashes (`md5sum /dev/mtdN` on the AP against the copies). `0:ART`
holds the unit's calibration and MACs and exists nowhere else.

## 4. Write OpenWrt to NAND slot 0

First check that Arista runs from slot 1: on the AP, `fw_printenv pri` must
print `pri=1`. With `pri=0`, the Arista system that runs is in slot 0 (Arista
upgrades into its spare slot and switches to it), and slot 1 holds an older
one, or none: writing slot 0 would erase the one that runs, and OpenWrt
takes its board data, PS keys and fallback from slot 1. Go on only if that
is what you want.

```
scp -O …-squashfs-factory.ubi root@<AP>:/tmp/factory.ubi
ssh root@<AP>
  M=$(grep '"ubi"' /proc/mtd | cut -d: -f1)
  ubidetach -p /dev/$M 2>/dev/null
  ubiformat /dev/$M -y -f /tmp/factory.ubi
```

## 5. Set the boot command

From the same RAM system, one U-Boot environment write:

```
fw_setenv -s - <<'EOF'
owrt_args console=ttyMSM0,115200n8 ubi.mtd=ubi rootwait panic=10 pcie_ports=compat
owrt_boot setenv fdt_high 0x4A3E0000; setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x10000000@0x0(ubi); ubi part ubi && ubi read 0x44000000 kernel && bootm 0x44000000#config@1
arista_boot setenv mtdids; setenv mtdparts; setenv fdt_high 0x4A400000; if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi; run ubootscript
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
pri 1
EOF
reboot
```

* `owrt_boot` boots OpenWrt from slot 0.
* `arista_boot` is Arista's own boot with Arista's settings put back first:
  its `bootkernel` sets `bootargs` only when `pri` changes and then saves the
  environment, so without this a fallback would boot, and save, OpenWrt's.
* `pri 1` makes Arista's boot use slot 1, the slot that is kept.

To boot Arista's firmware once: stop U-Boot and `run arista_boot`. To go back
to Arista for good: `fw_setenv bootcmd 'run ubootscript'` from OpenWrt (or
`setenv bootcmd run ubootscript; saveenv` at U-Boot), then reboot.

## First boot

* **Ethernet 1 is the uplink**, with no WAN. `br-lan` holds Ethernet 1 only
  and **takes its address by DHCP**, so look for the AP in your DHCP server's
  leases. It uses the unit's base MAC, the one on its label.
* **Ethernet 2 is free**, in no bridge, so a second cable to the same switch
  makes no loop. `arista-c260-net` puts it on the LAN, on a VLAN or a VXLAN,
  or bonds both ports (README.md).
* **Wi-Fi is off** until you turn it on, and SSH and LuCI have no password:
  set one first.
* **Failsafe mode** is at 192.168.1.1, as on any OpenWrt device: press `f`
  and Enter on the console when the boot offers it.
* On the first boot, and the first after each `sysupgrade`, the IPQ8074 radio
  takes its board data from the Arista slot as it starts, and the Bluetooth
  controller its PS keys. `logread` shows `arista-c260-board-data` and
  `arista-c260-bluetooth`.
* **Set the Wi-Fi country, then reboot once.** The board data is chosen by
  the wireless country, and a fresh install has none yet, so it starts with
  Arista's default. When the country is set, the file for it is copied in;
  the radio reads it from the next boot.

Later updates are ordinary `sysupgrade`s, which keep the settings.
