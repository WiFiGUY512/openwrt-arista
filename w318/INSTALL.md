# OpenWrt on the Arista W-318 — installation

OpenWrt takes Arista's slot 0 and keeps slot 1, Arista's system, as the
fallback. Installing is: boot this repo's initramfs from RAM (section 2),
then run `arista-w318-install` in it (sections 3 and 4).

## What you get

* OpenWrt on the IPQ6010 (2.4 + 5 GHz), the QCN9072 (6 GHz), the nRF52833
  Bluetooth module and the TPM.
* OpenWrt's kernel in NOR `0:HLOS`, its root (squashfs) in the eMMC
  partition `rootfs`, its settings in `rootfs_data`: Arista's slot 0.
  **Arista's system in slot 1 is kept**: it is the fallback, and it is where
  OpenWrt gets the 6 GHz card's firmware and the radios' board data from.
* The image contains no Arista or unit-specific files. When the radios first
  start, OpenWrt copies those files **unmodified from your unit's own Arista
  slot 1**; MAC addresses and calibration come from the unit's ART partition.

## Why it is installed this way

Arista's own boot (`bootipq`) checks a signature on the kernel, so OpenWrt
has a boot command of its own in the U-Boot environment: it reads OpenWrt's
kernel from `0:HLOS` and boots it, and if that fails runs Arista's boot with
`pri=1`, which is slot 1. Arista's boot saves the environment on every boot,
so the fallback first puts Arista's own settings back.

## You need

* The console cable: RJ-45 rollover (RS-232, not TTL) to the W-318's console
  port, 115200 8N1, no flow control.
* A TFTP server reachable on the uplink's network, holding
  `openwrt-qualcommax-ipq60xx-arista_w318-initramfs-uImage.itb`.
* `openwrt-qualcommax-ipq60xx-arista_w318-squashfs-sysupgrade.bin` on the PC.
* Both from the [releases page](https://github.com/WiFiGUY512/openwrt-arista/releases)
  or your own build's `out/w318/<version>/`.
* The uplink port cabled to that network (it takes PoE).
* For the backup: a USB stick (FAT32), or the PC.

## 1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot (the C-360's and C-260's too):

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Paste it repeatedly while the W-318 powers up until you see `IPQ6018#`, then
press Ctrl-C once to clear what is left on the line. Stop it before Arista's
boot runs: that boot saves the U-Boot environment each time.

## 2. Boot OpenWrt from RAM

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

Don't `saveenv`. OpenWrt takes an address by DHCP on the uplink (`br-lan`;
the three LAN ports are in no bridge until you add them); find it on the
console (`ip -4 addr show br-lan`) or in your DHCP server's leases. SSH as
root, no password. This alone writes nothing: a power cycle brings Arista
back.

Copy the sysupgrade image over from the PC:

```
scp -O openwrt-qualcommax-ipq60xx-arista_w318-squashfs-sysupgrade.bin root@<AP>:/tmp/
```

## 3. Check, and back up the flash (strongly recommended)

```
arista-w318-install --dry-run /tmp/openwrt-qualcommax-ipq60xx-arista_w318-squashfs-sysupgrade.bin
```

checks the unit, the flash layout, the image, ART and slot 1, and writes
nothing. With a USB stick in the W-318's USB port, mount it and add
`--backup`:

```
mount /dev/sda1 /mnt
arista-w318-install --dry-run --backup /mnt /tmp/openwrt-qualcommax-ipq60xx-arista_w318-squashfs-sysupgrade.bin
```

It saves every NOR partition, the GPT and the two eMMC partitions the
install writes, gzipped, each checked against the flash, in a directory named
after the unit. Copy that directory to the PC. **`0:ART` holds this unit's
calibration and MACs and exists nowhere else.**

## 4. Install

```
arista-w318-install /tmp/openwrt-qualcommax-ipq60xx-arista_w318-squashfs-sysupgrade.bin
```

It runs the checks again, asks for the last four hex digits of the unit's
MAC (as on its label), then writes, in this order:

1. the U-Boot environment, once: `owrt_boot`, `arista_boot`, `bootcmd`,
   `pri=1` (read back);
2. `0:HLOS` erased (read back blank), so that from here until the kernel is
   written U-Boot finds no OpenWrt kernel and boots Arista's slot 1;
3. the root to `rootfs` (read back);
4. the first 4 MiB of `rootfs_data` wiped;
5. the kernel to `0:HLOS` (read back).

Should it stop part way, the unit boots Arista's slot 1, and the install can
be run again from section 2. The last line says `W318-INSTALL-RESULT: OK` or
what failed. Then `reboot`.

## First boot

* OpenWrt boots from flash by itself; its first boot makes the overlay on
  `rootfs_data`. It takes an address by DHCP on the uplink, as in section 2.
* **Failsafe mode** is at 192.168.1.1, as on any OpenWrt device: press `f`
  and Enter on the console when the boot offers it.
* Wi-Fi starts off, as OpenWrt's default. The radios take Arista's FCC_CE
  board data (the US and the EU) until a country is set; then the country's
  group's, from the radios' next start (a reboot).
* Updates: `sysupgrade` with a newer `squashfs-sysupgrade.bin` (LuCI or the
  command line); it keeps the settings unless told not to. Slot 1 is never
  touched.

## Back to Arista

At the `IPQ6018#` prompt (section 1), `run arista_boot` boots Arista's slot 1
once. For good, put Arista's boot command back (one environment write):

```
setenv bootcmd 'env default default_env_version; if test -n "${default_env_version}"; then run ubootscriptv2; else run ubootscript; fi;'
saveenv
```

Arista then boots slot 1 (`pri=1`); slot 0 holds OpenWrt until Arista
upgrades into it.
