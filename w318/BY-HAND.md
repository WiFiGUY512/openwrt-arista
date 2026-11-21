# OpenWrt on the Arista W-318: installing by hand

**Most installs do not need this page.** The network installer in
[INSTALL.md](INSTALL.md) does all of this from a PC, with no cable. This is
the console procedure: for an AP the installer cannot reach or log in to, or
to see every step.

OpenWrt takes Arista's slot 0 and keeps slot 1, Arista's system, as the
fallback. Installing is: boot the initramfs from RAM (section 2), then run
`arista-w318-install` in it (sections 3 and 4). Done this way on a unit.

## Why it is installed this way

Arista's own boot (`bootipq`) checks a signature on the kernel, so OpenWrt
has a boot command of its own in the U-Boot environment: it reads OpenWrt's
kernel from `0:HLOS` and boots it, and if that fails runs Arista's boot with
`pri=1`, which is slot 1. Arista's boot saves the environment on every boot,
so the fallback first puts Arista's own settings back.

## You need

* **The console cable:** RJ-45 rollover (RS-232, not TTL) to the W-318's
  console port, 115200 8N1, no flow control.
* **A TFTP server** reachable on the uplink's network.
* **The images,** from the newest build for the W-318 in
  [openwrt-arista-installer](https://github.com/WiFiGUY512/openwrt-arista-installer/releases)
  (its [STATUS.md](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/STATUS.md)
  lists them):
  `openwrt-qualcommax-ipq60xx-arista_w-318-initramfs-uImage.itb` for the TFTP
  server, and `openwrt-qualcommax-ipq60xx-arista_w-318-squashfs-sysupgrade.bin`
  on the PC. This repository's own releases are 25.12 builds, named
  `arista_w318` instead; they boot the same way (`config@cp01-c3`).
* The uplink port cabled to that network (it takes PoE).
* **For the backup:** a FAT32 drive for the W-318's USB port.

## 1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot:

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
tftpboot 0x60000000 openwrt-qualcommax-ipq60xx-arista_w-318-initramfs-uImage.itb
bootm 0x60000000#config@cp01-c3
```

Don't `saveenv`. OpenWrt takes an address by DHCP on the uplink (`br-lan`);
find it on the console (`ip -4 addr show br-lan`) or in your DHCP server's
leases. SSH as root, no password. This alone writes nothing: a power cycle
brings Arista back.

Copy the sysupgrade image over from the PC:

```
scp -O openwrt-qualcommax-ipq60xx-arista_w-318-squashfs-sysupgrade.bin root@<AP>:/tmp/
```

## 3. Check, and back up the flash

```
arista-w318-install --dry-run /tmp/openwrt-qualcommax-ipq60xx-arista_w-318-squashfs-sysupgrade.bin
```

checks the unit, the flash layout, the image, ART and slot 1, and writes
nothing. With the drive in the W-318's USB port, mount it and add
`--backup`:

```
mount /dev/sda1 /mnt
arista-w318-install --dry-run --backup /mnt /tmp/openwrt-qualcommax-ipq60xx-arista_w-318-squashfs-sysupgrade.bin
```

It saves every NOR partition, the GPT and the two eMMC partitions the
install writes, gzipped, each checked against the flash, in a directory named
after the unit. Copy that directory to the PC. **`0:ART` holds this unit's
calibration and MACs and exists nowhere else.**

## 4. Install

```
arista-w318-install /tmp/openwrt-qualcommax-ipq60xx-arista_w-318-squashfs-sysupgrade.bin
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

OpenWrt boots from flash by itself; its first boot makes the overlay on
`rootfs_data`. What to do after that is in
[INSTALL.md](INSTALL.md#after-the-install).

## Back to Arista's firmware

At the `IPQ6018#` prompt (section 1), `run arista_boot` boots Arista's slot 1
once. For good, put Arista's boot command back (one environment write):

```
setenv bootcmd 'env default default_env_version; if test -n "${default_env_version}"; then run ubootscriptv2; else run ubootscript; fi;'
saveenv
```

Arista then boots slot 1 (`pri=1`); slot 0 holds OpenWrt until Arista
upgrades into it.
