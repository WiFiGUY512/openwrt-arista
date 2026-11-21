# OpenWrt on the Arista W-118: installing by hand

**Most installs do not need this page.** The network installer in
[INSTALL.md](INSTALL.md) does all of this from a PC, with the case closed.
This is the console procedure: for an AP the installer cannot reach or log in
to, or to see every step.

OpenWrt goes into the half of the NAND that Arista's system leaves unused.
Both of Arista's slots stay, and Arista's own boot is the fallback.
Installing is: boot OpenWrt's initramfs from RAM, back up the flash, write
one U-Boot environment change, then `sysupgrade -n`. Done this way on a unit.

## How it boots

A boot command of OpenWrt's own runs first: it attaches `ubi`, reads the
`kernel` volume and boots it with `bootm`. If that volume is missing or fails
its check, Arista's own boot (`ubootscript`) runs as before.

## You need

* **The console:** a 3.3 V USB-TTL adapter on the internal header J12 (open
  the cover). Pin 1 is 3.3 V (leave it unconnected), pin 2 GND, pins 3 and 4
  TX and RX. 115200 8N1.
* **A TFTP server** on the uplink's network.
* **The images,** from the newest build for the W-118 in
  [openwrt-arista-images](https://github.com/WiFiGUY512/openwrt-arista-images/releases)
  (its [STATUS.md](https://github.com/WiFiGUY512/openwrt-arista-images/blob/main/STATUS.md)
  lists them), or from `main/build-main.sh ipq40xx`:
  `openwrt-ipq40xx-generic-arista_w-118-initramfs-zImage.itb` for the TFTP
  server, and `openwrt-ipq40xx-generic-arista_w-118-squashfs-sysupgrade.bin`.

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

Copy the sysupgrade image to `/tmp`, then:

```
sysupgrade -n /tmp/openwrt-ipq40xx-generic-arista_w-118-squashfs-sysupgrade.bin
```

It creates the UBI in `ubi`, writes the kernel and root volumes and reboots
into OpenWrt. What to do after the first boot is in
[INSTALL.md](INSTALL.md#after-the-install).

## Back to Arista's firmware

`fw_setenv bootcmd 'run ubootscript'` and reboot: Arista's system boots as
before, from the slot its `pri` names. OpenWrt's volumes stay in `ubi`
until something else is written there.
