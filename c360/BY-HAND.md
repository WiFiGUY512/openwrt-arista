# OpenWrt on the Arista C-360: installing by hand

**Most installs do not need this page.** The network installer in
[INSTALL.md](INSTALL.md) does all of this from a PC, with no cable. This is
the console procedure behind it: for an AP the installer cannot reach or log
in to, or to see every step.

The steps are: stop the boot loader, start OpenWrt from memory over TFTP,
back up the flash, write OpenWrt to slot 0, and set the boot command once.
They were run by hand on two units, with the 25.12 images.

A halfway route: do steps 1 and 2, then let the network installer do the rest
from your PC with `python arista-field.py --installer-at <the AP's address>`.

## You need

* **The console cable:** RJ-45 rollover (RS-232, not TTL) to the C-360's
  console port, 115200 8N1, no flow control. A standard Cisco/switch console
  cable gives garbage on this port.
* **A TFTP server** reachable on the AP's untagged network.
* **The images,** from the newest build for the C-360 in
  [openwrt-arista-installer](https://github.com/WiFiGUY512/openwrt-arista-installer/releases)
  (its [STATUS.md](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/STATUS.md)
  lists them):
  `openwrt-qualcommax-ipq807x-arista_c-360-initramfs-uImage.itb` for the TFTP
  server, and `...-arista_c-360-squashfs-factory.ubi` on the PC.

Those are OpenWrt main builds, and the commands below are for them. This
repository's own releases are 25.12 builds, which differ in a few places:
see [With a 25.12 image](#with-a-2512-image).

## Why it is installed this way

* The QCN9074 cards only run Arista's build of the Qualcomm firmware
  (WLAN.HK.2.5.r4). All fifteen public ath11k-firmware builds tested
  (2.5.0.1 – 2.9.0.1) stop at the QMI capability request on these cards. So
  Arista's system stays in slot 1, and OpenWrt takes that firmware from it.
* Arista's normal boot path (`bootipq`) checks image signatures; plain `bootm`
  does not. The install therefore sets its own U-Boot `bootcmd`, which loads
  the kernel from OpenWrt's UBI and falls back to Arista's boot if that fails.

## 1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot:

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Paste it repeatedly while the AP boots until you see `IPQ807x#`. **Do not let
Arista's firmware boot by accident while you are at it**: its boot script
runs `saveenv` every time.

## 2. Boot the OpenWrt installer from RAM

At `IPQ807x#` (nothing below is saved; `saveenv` is never used here):

```
setenv ipaddr <AP address>
setenv serverip <TFTP server>
setenv fdt_high 0x4A3E0000
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0
tftpboot 0xA0000000 openwrt-qualcommax-ipq807x-arista_c-360-initramfs-uImage.itb
bootm 0xA0000000#config@hk09
```

`panic=0` makes a crashing installer halt instead of rebooting: a reboot
without someone stopping U-Boot boots Arista, whose script saves the U-Boot
environment.

The RAM system takes an address by DHCP on Ethernet 1. SSH as root, no
password.

## 3. Back up the flash

The installer sees all partitions; only `rootfs` (NAND slot 0) and the U-Boot
environment are writable. From a PC:

```
for n in $(ssh root@<AP> "cut -d: -f1 /proc/mtd | grep mtd"); do
  ssh root@<AP> "cat /dev/$n" > c360-$n.bin
done
ssh root@<AP> cat /proc/mtd > c360-proc-mtd.txt
```

Check hashes (`sha256sum /dev/mtdN` on the AP against the copies). The ART
partition holds the unit's calibration and MAC addresses and exists nowhere
else.

## 4. Write OpenWrt to NAND slot 0

```
scp ...-squashfs-factory.ubi root@<AP>:/tmp/factory.ubi
ssh root@<AP>
  M=$(grep '"rootfs"' /proc/mtd | cut -d: -f1)
  ubidetach -p /dev/$M 2>/dev/null
  ubiformat /dev/$M -y -f /tmp/factory.ubi
```

## 5. Set the boot command

From the installer, one U-Boot environment write, the same one
`arista-c360-install` makes:

```
fw_setenv -s - <<'EOF'
owrt_args console=ttyMSM0,115200n8 rootwait panic=10
owrt_parts setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x18000000@0x0(ubi)
owrt_load ubi part ubi && ubi read 0x44000000 kernel
owrt_boot setenv fdt_high 0x4A3E0000; run owrt_parts owrt_load && bootm 0x44000000#config@hk09
arista_unset setenv mtdids; setenv mtdparts; setenv fdt_high 0x4A400000
arista_args if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi
arista_boot run arista_unset arista_args ubootscript
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
pri 1
EOF
reboot
```

* `owrt_boot` boots OpenWrt from slot 0. `fdt_high 0x4A3E0000` matters:
  Arista's default 0x4A400000 places the device tree on top of U-Boot's own
  control DTB.
* `arista_boot` is Arista's own boot with Arista's settings put back first:
  its `bootkernel` sets `bootargs` only when `pri` changes and then saves the
  environment, so without this a fallback would boot, and save, OpenWrt's
  `bootargs`, `fdt_high` and partition table.
* `pri 1` makes Arista's boot use slot 1, the slot that is kept.

What to do after the first boot is in [INSTALL.md](INSTALL.md#after-the-install).

## Keeping your settings across the install (optional)

`sysupgrade -b` refuses to run from the RAM installer. To carry settings
(e.g. a management VLAN) into the first boot, put a tarball of the wanted
`/etc/config/*` files at the root of the `rootfs_data` volume as
`sysupgrade.tgz` after step 4; OpenWrt restores it on first boot:

```
ubiattach -p /dev/$M -d 0
mkdir -p /tmp/rd && mount -t ubifs ubi0:rootfs_data /tmp/rd
tar czf /tmp/rd/sysupgrade.tgz -C / etc/config/network etc/config/firewall
umount /tmp/rd && ubidetach -d 0
```

If you add an interface (e.g. a VLAN) for management, put it in a firewall
zone that accepts input (`lan`), or SSH will be refused.

## Back to Arista's firmware

* **Once:** stop U-Boot (step 1) and type `run arista_boot`. It boots Arista
  from slot 1.
* **For good:** from OpenWrt, `fw_setenv bootcmd 'run ubootscript'` (or
  `setenv bootcmd run ubootscript; saveenv` at U-Boot), then reboot.

## An older boot command

Units installed with an earlier installer or guide have an earlier boot
command, whose fallback is a bare `run ubootscript`: if OpenWrt ever failed
to load, Arista would start with OpenWrt's settings and save them.
`fw_printenv bootcmd` shows which a unit has; from OpenWrt, one write brings
an earlier one up to date:

```
fw_setenv -s - <<'EOF'
arista_boot setenv mtdids; setenv mtdparts; setenv fdt_high 0x4A400000; if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi; run ubootscript
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
EOF
```

## With a 25.12 image

This repository's own releases, and `./build.sh c360`, make 25.12 images.
They are named `arista_c360` (board name `arista,c360`), and the steps differ
so:

* **Step 2:** add `pcie_ports=compat` to `bootargs`, and boot `config@1`:

  ```
  setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat
  tftpboot 0xA0000000 openwrt-qualcommax-ipq807x-arista_c360-initramfs-uImage.itb
  bootm 0xA0000000#config@1
  ```

* **Steps 3 and 4:** the device tree names NAND slot 0 `ubi`, not `rootfs`,
  and the other partitions in upper case (`0:ART`): use
  `M=$(grep '"ubi"' /proc/mtd | cut -d: -f1)`.
* **Step 5:** the write is this instead:

  ```
  fw_setenv -s - <<'EOF'
  owrt_args console=ttyMSM0,115200n8 ubi.mtd=ubi rootwait panic=10 pcie_ports=compat
  owrt_boot setenv fdt_high 0x4A3E0000; setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x18000000@0x0(ubi); ubi part ubi && ubi read 0x44000000 kernel && bootm 0x44000000#config@1
  arista_boot setenv mtdids; setenv mtdparts; setenv fdt_high 0x4A400000; if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi; run ubootscript
  bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
  pri 1
  EOF
  reboot
  ```

* **First boot:** Ethernet 2 is in no bridge, so a second cable to the same
  switch makes no loop; `arista-c360-net` puts it on the LAN.
