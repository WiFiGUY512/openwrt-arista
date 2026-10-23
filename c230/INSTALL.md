# OpenWrt on the Arista C-230: installation

The C-260's way (its [INSTALL.md](../c260/INSTALL.md) explains the why):
OpenWrt goes to NAND slot 0 as UBI, Arista's system stays in slot 1 as the
fallback, and U-Boot is given a boot command that tries OpenWrt first. A
console is needed (RJ-45, RS-232, 115200 8N1). Done this way on one unit on
2026-10-22.

The images: `out/main/<version>/c230/` from `main/build-main.sh ipq807x`:
`openwrt-qualcommax-ipq807x-arista_c-230-initramfs-uImage.itb` (the RAM
installer), `...-squashfs-factory.ubi`, `...-squashfs-sysupgrade.bin`.

Unlike the C-260s seen so far, a C-230 may run Arista from slot 0
(`pri=0`). Installing replaces slot 0 all the same: slot 1 holds Arista too,
and the boot command makes it the fallback (`pri=1`). Back the flash up first
(step 3): Arista's slot-0 settings are lost.

## 1. Stop U-Boot

Paste `s6.D5r4Gnb89ZEWSW6Kq.` repeatedly while it boots, until `IPQ807x#`.
Do not let Arista's firmware boot meanwhile: its boot script saves the U-Boot
environment on every boot.

## 2. Boot the installer from RAM

At `IPQ807x#` (nothing below is saved):

```
setenv ipaddr <AP address>
setenv serverip <TFTP server>
setenv fdt_high 0x4A3E0000
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0
tftpboot 0x60000000 openwrt-qualcommax-ipq807x-arista_c-230-initramfs-uImage.itb
bootm 0x60000000#config@ac02
```

The installer's device tree appends `ubi.mtd=rootfs`, so it attaches slot 0
(Arista's UBI) as it boots; UBI may move a few of its blocks (bit-flip
scrubbing, as Arista's own boot does).

## 3. Back up the flash

Every partition is readable from the installer (`/proc/mtd`); only `rootfs`
(slot 0) and `0:appsblenv` are writable. From a PC:

```
for n in $(ssh root@<AP> "cut -d: -f1 /proc/mtd | grep mtd"); do
  ssh root@<AP> "cat /dev/$n" > c230-$n.bin
done
```

ART (the calibration and MACs) exists nowhere else.

## 4. Install

Copy `factory.ubi` and a `SHA256SUMS` for it (a line `<sha256>  factory.ubi`
and the kernel and rootfs volumes' lines, as `c360/tools/ubi_extract.py`
`sums()` makes them) to `/tmp/c230/`, then:

```
arista-c230-install --dry-run --no-backup --stick /tmp/c230
arista-c230-install --no-backup --stick /tmp/c230
```

It checks the unit (a C-230, from RAM, the flash layout, slot 1's Arista
system and kernel), writes the U-Boot environment once (the boot command
below and `pri=1`), then writes slot 0 and reads its volumes back. Without
`--no-backup` it backs every partition up to the stick's directory itself
(512 MiB free needed). It asks for the MAC's last four hex digits first
unless given `--yes`. Then `reboot`.

The boot command, for doing it by hand (one `fw_setenv -s` write):

```
owrt_args console=ttyMSM0,115200n8 rootwait panic=10
owrt_parts setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x10000000@0x0(ubi)
owrt_load ubi part ubi && ubi read 0x44000000 kernel
owrt_boot setenv fdt_high 0x4A3E0000; run owrt_parts owrt_load && bootm 0x44000000#config@ac02
arista_unset setenv mtdids; setenv mtdparts; setenv fdt_high 0x4A400000
arista_args if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi
arista_boot run arista_unset arista_args ubootscript
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
pri 1
```

## First boot

About 30 s from U-Boot to the console. lan1 and lan2 are in `br-lan`, by
DHCP; cable one of them, or turn on STP: two on the same switch make a loop.
There is no root password yet.

To boot Arista once: stop U-Boot and `run arista_boot` (it boots slot 1, and
its own boot then saves the environment). To go back to Arista for good:
`fw_setenv bootcmd 'run ubootscript'`.

## Updating

`sysupgrade` with `...-squashfs-sysupgrade.bin` writes slot 0 again and
keeps the settings (and the Bluetooth PS keys file); the U-Boot environment
is not touched.
