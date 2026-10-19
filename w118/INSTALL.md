# OpenWrt on the Arista W-118 — installation

OpenWrt goes into the half of the NAND that Arista's system leaves unused.
Both of Arista's slots stay, and Arista's own boot is the fallback.
Installing is: boot OpenWrt's initramfs from RAM, back up the flash, write
one U-Boot environment change, then `sysupgrade -n`.

## What you get

* OpenWrt on the IPQ4019 (2.4 + 5 GHz), the QCA9882 scanning radio and the
  Bluetooth controller.
* OpenWrt's kernel, root (squashfs) and settings (UBIFS) as UBI volumes in
  NAND `ubi` (0x8000000, the upper 128 MiB).
* **Arista's system is kept in full**: both kernels in NOR, both roots in the
  lower NAND half. Nothing of Arista's is written.
* MACs and calibration come from the unit's ART; the radios' board data is
  Arista's own, carried in the image (`ipq-wifi-arista_w-118`).

## How it boots

A boot command of OpenWrt's own runs first: it attaches `ubi`, reads the
`kernel` volume and boots it with `bootm`. If that volume is missing or fails
its check, Arista's own boot (`ubootscript`) runs as before.

## You need

* The console: a 3.3 V USB-TTL adapter on the internal header J12 (open the
  cover). Pin 1 is 3.3 V (leave it unconnected), pin 2 GND, pins 3 and 4
  TX and RX. 115200 8N1.
* A TFTP server on the uplink's network, with
  `openwrt-ipq40xx-generic-arista_w-118-initramfs-zImage.itb`.
* `openwrt-ipq40xx-generic-arista_w-118-squashfs-sysupgrade.bin`.
  Both from `main/build-main.sh ipq40xx` (`out/main/<version>/w118/`).

## 1. Stop U-Boot

U-Boot shows no countdown and stops on any key, but only in the moment after
the boot ROM's banner: send keys (Enter) from power-on. Do not let Arista's
system boot meanwhile: its boot script saves the environment on every boot.

## 2. Boot OpenWrt from RAM (nothing is written)

```
setenv ipaddr <AP address>; setenv serverip <TFTP server>
setenv bootargs console=ttyMSM0,115200n8
tftpboot 0x84000000 openwrt-ipq40xx-generic-arista_w-118-initramfs-zImage.itb
bootm 0x84000000
```

It takes an address by DHCP on the uplink; root logs in without a password.

## 3. Back up

Copy every MTD partition off the unit (`/proc/mtd`; `cat /dev/mtdN`), at
least `0:art`: it holds this unit's calibration and MACs and exists nowhere
else.

## 4. The boot command (the one environment write)

```
fw_setenv -s - <<'EOF'
owrt_args console=ttyMSM0,115200n8
owrt_ubi setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x8000000@0x8000000(ubi)
owrt_load ubi part ubi && ubi read 0x84000000 kernel && iminfo 0x84000000
owrt_boot run owrt_ubi && run owrt_load && bootm 0x84000000
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run ubootscript
EOF
```

Arista's own variables (`pri`, `sr`, `rp`, `ubootscript`, …) stay as they
are.

## 5. Install

```
sysupgrade -n /tmp/openwrt-ipq40xx-generic-arista_w-118-squashfs-sysupgrade.bin
```

It creates the UBI in `ubi`, writes the kernel and root volumes and reboots
into OpenWrt. Later upgrades are ordinary sysupgrades.

## Back to Arista

`fw_setenv bootcmd 'run ubootscript'` and reboot: Arista's system boots as
before, from the slot its `pri` names. OpenWrt's volumes stay in `ubi`
until something else is written there.

## Without the console (not yet done)

Arista's own kernel sees only its two NAND slots and the NOR, so an install
from a root shell on Arista's system would be Arista's own upgrade:
OpenWrt's zImage FIT to `0:HLOS1`, its root to `rootfs2`, then
`fw_setenv pri 1`. On a unit, from the console, OpenWrt's kernel booted from
`0:HLOS1` this way (Arista's `bootipq` with its own slot-1 boot arguments),
its root then still in `ubi`; a root in `rootfs2` is not yet tried.
Arista's counter would fall back to slot 0 after three boots that OpenWrt
does not mark good (`sr`).
