# OpenWrt on the Arista C-460: installation

**Draft: not yet run on a unit.** The steps below follow the port's standard
layout and every piece of them has been checked on its own (RAM boots, the
environment readable from OpenWrt, `sysupgrade -T`, U-Boot reading slot 0
into RAM); the install itself is tested next, on one unit, before a release.

OpenWrt goes to eMMC slot 0 (`0:HLOS` for the kernel, `rootfs` for the root
file system), Arista's system stays in slot 1 (`0:HLOS_1`, `rootfs_1`) as the
fallback, and U-Boot is given a boot command that tries OpenWrt first. A
console is needed (RJ-45, RS-232, 115200 8N1).

The images: `out/main/<version>/c460/` from `main/build-main.sh ipq95xx`:
`openwrt-qualcommbe-ipq95xx-arista_c-460-initramfs-uImage.itb` (the RAM
installer) and `...-squashfs-sysupgrade.bin`.

The C-460's U-Boot checks Arista's signature on the kernel and root file
system it boots with its own boot command (Secure Boot is on). Its `bootm`
does not, so OpenWrt is booted with `bootm`. Arista's kernel in slot 0 is
Qualcomm's signed ELF image; OpenWrt's is a plain FIT.

A C-460 runs Arista from slot 0 (`pri=0`) with the same system in slot 1.
Installing replaces slot 0, and the boot command makes slot 1 the fallback
(`pri=1`). Back up first (step 3): Arista's slot-0 settings are lost.

## 1. Stop U-Boot

Paste `s6.D5r4Gnb89ZEWSW6Kq.` repeatedly while it boots, until `IPQ9574#`
(a plain Enter does not stop it). Do not let Arista's firmware boot
meanwhile: its boot saves the U-Boot environment every time.

## 2. Boot the installer from RAM

At `IPQ9574#` (nothing below is saved):

```
setenv ipaddr <AP address>
setenv serverip <TFTP server>
tftpboot 0x44000000 openwrt-qualcommbe-ipq95xx-arista_c-460-initramfs-uImage.itb
bootm 0x44000000
```

No `bootargs` are needed: the image adds its own root. Keep anything read
into RAM at `0x44000000` under about 96 MiB: U-Boot's stack is at
`0x4A27FA80`. The installer takes its address by DHCP on the PoE port (lan1).

## 3. Back up

To another machine, with checksums:

- every NOR partition (`/proc/mtd`); `0:ART` holds the unit's calibration
  data and MAC addresses and exists nowhere else;
- slot 0 of the eMMC: `/dev/mmcblk0p1` (`0:HLOS`), `/dev/mmcblk0p3`
  (`rootfs`) and `/dev/mmcblk0p5` (`rootfs_data`, Arista's settings).

## 4. The boot command

One environment write, made before OpenWrt is written (step 5 reboots):

```
fw_setenv -s - <<'EOF'
owrt_args console=ttyMSM0,115200n8 rootwait panic=10
owrt_load mmc read 0x44000000 0x22 0x10000
owrt_boot run owrt_load && bootm 0x44000000
arista_boot setenv bootargs ${default_bootargs}; run ubootscript
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
pri 1
EOF
```

U-Boot reads all of `0:HLOS` (LBA 0x22, 0x10000 blocks, 32 MiB) into RAM and
boots it. If that fails, it runs Arista's own boot (`ubootscript`) with
Arista's boot arguments, which takes slot 1. Once the boot command no longer
runs `ubootscript`, Arista's U-Boot stops saving its environment on every
boot.

## 5. Write OpenWrt to slot 0

Copy the sysupgrade image to `/tmp`, then:

```
sysupgrade -n /tmp/openwrt-qualcommbe-ipq95xx-arista_c-460-squashfs-sysupgrade.bin
```

It writes the kernel to `0:HLOS` and the root file system to `rootfs`, and
reboots into OpenWrt from slot 0.

## Updating

`sysupgrade` with `...-squashfs-sysupgrade.bin` writes slot 0 again and
keeps the settings.

## Going back to Arista

Once, from the U-Boot prompt: `run arista_boot` (slot 1).

For good:

```
fw_setenv bootcmd 'run ubootscript;'
reboot
```

Slot 1 boots (`pri=1`). To have Arista in slot 0 again, write the backup of
`mmcblk0p1`, `p3` and `p5` back and set `pri` to 0.
