# OpenWrt on the Arista C-260: installing by hand

**Most installs do not need this page.** The network installer in
[INSTALL.md](INSTALL.md) does all of this from a PC, with no cable. This is
the console procedure behind it: for an AP the installer cannot reach or log
in to, or to see every step.

The steps are: stop the boot loader, start OpenWrt from memory over TFTP,
back up the flash, write OpenWrt to slot 0, and set the boot command once.
They were run by hand on one unit, with the 25.12 images, and so was the
fallback: `arista_boot` booted Arista's slot 1 with Arista's own settings,
and after a power cycle OpenWrt came back by itself.

A halfway route: do steps 1 and 2, then let the network installer do the rest
from your PC with `python arista-field.py --installer-at <the AP's address>`.

## You need

* **The console cable:** RJ-45 rollover (RS-232, not TTL) to the C-260's
  console port, 115200 8N1, no flow control.
* **A TFTP server** reachable on the AP's untagged network.
* **The images.** The commands below are written for this repository's own
  releases and `./build.sh c260`, which make 25.12 images:
  `openwrt-qualcommax-ipq807x-arista_c260-initramfs-uImage.itb` for the TFTP
  server, and `...-arista_c260-squashfs-factory.ubi` on the PC. The builds in
  [openwrt-arista-installer](https://github.com/WiFiGUY512/openwrt-arista-installer/releases)
  are OpenWrt main: see [With an OpenWrt main image](#with-an-openwrt-main-image).

## Why it is installed this way

Arista's normal boot (`bootipq`) picks its kernel from SPI NOR by the
BOOTCONFIG partition, and switching that means writing the boot chain's own
partitions. OpenWrt's kernel goes into UBI in NAND slot 0 instead, and its own
U-Boot `bootcmd` loads it from there, falling back to Arista's boot if that
fails. U-Boot, the boot chain, ART and slot 1 are never written.

## 1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot:

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Paste it repeatedly while the AP boots until you see `IPQ807x#`, then press
Ctrl-C once to clear what is left on the line. **Do not let Arista's
firmware boot by accident while you are at it**: its boot script runs
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

The RAM system takes an address by DHCP on its LAN, Ethernet 1. SSH as root,
no password.

## 3. Back up the flash

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
scp -O ...-squashfs-factory.ubi root@<AP>:/tmp/factory.ubi
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

What to do after the first boot is in
[INSTALL.md](INSTALL.md#after-the-install). On a 25.12 image Ethernet 2 is in
no bridge, so a second cable to the same switch makes no loop.

## With an OpenWrt main image

The builds in openwrt-arista-installer, and `main/build-main.sh ipq807x`, are
named `arista_c-260` (board name `arista,c-260`). Use that build's files for
every step, and:

* **Step 2:** no `pcie_ports=compat`, and boot `config@hk01`:

  ```
  setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0
  tftpboot 0x60000000 openwrt-qualcommax-ipq807x-arista_c-260-initramfs-uImage.itb
  bootm 0x60000000#config@hk01
  ```

* **Step 3:** the device tree names NAND slot 0 `rootfs`, not `ubi`.
* **Steps 4 and 5:** let the RAM system's own installer do both. It checks
  the unit and slot 1, makes the one environment write for the OpenWrt it is,
  writes slot 0 and reads it back. On the AP, with `<tag>` the build's tag:

  ```
  mkdir -p /tmp/c260 && cd /tmp/c260
  wget -O factory.ubi https://github.com/WiFiGUY512/openwrt-arista-installer/releases/download/<tag>/openwrt-qualcommax-ipq807x-arista_c-260-squashfs-factory.ubi
  wget -O SHA256SUMS https://github.com/WiFiGUY512/openwrt-arista-installer/releases/download/<tag>/c260-install-SHA256SUMS
  arista-c260-install --dry-run --no-backup --stick /tmp/c260
  arista-c260-install --no-backup --stick /tmp/c260
  reboot
  ```

  The first `arista-c260-install` only checks. The second asks for the last
  four hex digits of the AP's MAC address, then installs. Wait a minute after
  the RAM system starts before the downloads: they are HTTPS and fail until
  the AP has set its clock. Without internet, copy the two files from the PC
  with `scp -O`, under those names.

  This is what the network installer runs on a C-260; from the console it
  has not been run end to end.

## Back to Arista's firmware

* **Once:** stop U-Boot (step 1) and type `run arista_boot`. It boots Arista
  from slot 1.
* **For good:** from OpenWrt, `fw_setenv bootcmd 'run ubootscript'` (or
  `setenv bootcmd run ubootscript; saveenv` at U-Boot), then reboot.
