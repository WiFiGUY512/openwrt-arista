# OpenWrt on the Arista C-200: installation

The C-230's way: OpenWrt goes to NAND slot 0 as UBI, Arista's system stays
in slot 1 as the fallback, and U-Boot is given a boot command that tries
OpenWrt first. A console is needed (RJ-45, RS-232, 115200 8N1). Done this
way on one unit on 2026-11-02.

The images: `out/main/<version>/c200/` from `main/build-main.sh ipq60xx`:
`openwrt-qualcommax-ipq60xx-arista_c-200-initramfs-uImage.itb` (the RAM
installer), `...-squashfs-factory.ubi`, `...-squashfs-sysupgrade.bin`.

A C-200 may run Arista from slot 0 (`pri=0`, as the one seen did).
Installing replaces slot 0 all the same: slot 1 holds Arista too, and the
boot command makes it the fallback (`pri=1`). Back the flash up first
(step 3): Arista's slot-0 settings are lost.

## 1. Stop U-Boot

Paste `s6.D5r4Gnb89ZEWSW6Kq.` repeatedly while it boots, until `IPQ6018#`.
Do not let Arista's firmware boot meanwhile: its boot script saves the U-Boot
environment on every boot.

## 2. Boot the installer from RAM

At `IPQ6018#` (nothing below is saved):

```
setenv ipaddr <AP address>
setenv serverip <TFTP server>
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0
tftpboot 0x60000000 openwrt-qualcommax-ipq60xx-arista_c-200-initramfs-uImage.itb
bootm 0x60000000#config@cp01-c3
```

The installer takes its address by DHCP on the port.

## 3. Back up the flash

Every MTD partition (`/proc/mtd`) to another machine, with checksums. `0:ART`
holds the unit's calibration data and MAC address and exists nowhere else.

## 4. Write OpenWrt to slot 0

Copy the factory image to `/tmp`, then (slot 0 is `rootfs`, mtd0):

```
ubidetach -p /dev/mtd0
ubiformat /dev/mtd0 -y -f /tmp/openwrt-qualcommax-ipq60xx-arista_c-200-squashfs-factory.ubi
```

## 5. The boot command

One environment write, then reboot:

```
fw_setenv -s - <<'EOF'
owrt_args console=ttyMSM0,115200n8 rootwait panic=10
owrt_parts setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x10000000@0x0(ubi)
owrt_load ubi part ubi && ubi read 0x44000000 kernel
owrt_boot run owrt_parts owrt_load && bootm 0x44000000#config@cp01-c3
arista_unset setenv mtdids; setenv mtdparts
arista_args if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi
arista_boot run arista_unset arista_args ubootscript
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run arista_boot
pri 1
EOF
reboot
```

U-Boot loads OpenWrt's kernel from the UBI volume `kernel` in slot 0; if
that fails, it puts Arista's partition settings and bootargs back and runs
Arista's own boot (`ubootscript`), which takes slot 1. `fdt_high` stays
Arista's (0x48500000).

## Updating

`sysupgrade` with `...-squashfs-sysupgrade.bin` writes slot 0's UBI volumes
(not yet run on a unit).

## Going back to Arista

```
fw_setenv bootcmd 'run ubootscript'
reboot
```

Slot 1 boots (`pri=1`). Slot 0's Arista contents are in your backup.

## Its address

OpenWrt's DHCP client releases its lease when it shuts down, so a DHCP
server may hand out another address on each boot. Reserve one for the
unit's MAC (lan1, the label MAC) or its client ID.
