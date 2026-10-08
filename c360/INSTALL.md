# OpenWrt on the Arista C-360 — installation

Status: the manual steps (TFTP, sections B1–B5) were verified on one unit on
2026-10-07. The USB stick method (section A) is built and checked in
simulation and against the real flash backups, but **it has not been run on a
unit yet**.

## What you get

* OpenWrt on the IPQ8074 (2.4 + 5 GHz) and both QCN9074 cards: one 6 GHz
  serving radio and the 2.4/5/6 GHz multifunction radio (airscan).
* OpenWrt lives in NAND slot 0. **Arista's system in slot 1 is kept**: it is
  the fallback, and it is where OpenWrt gets the QCN9074 firmware from.
* The image contains no Arista or unit-specific files. On first boot,
  `arista-c360-wifi-fw` copies the Wi-Fi firmware and board files **unmodified
  from your unit's own Arista slot 1**; MAC addresses and calibration come from
  the unit's ART partition. If slot 1 is erased, the radios stay off.

## Why it is installed this way

* The QCN9074 cards only run Arista's build of the Qualcomm firmware
  (WLAN.HK.2.5.r4). All fifteen public ath11k-firmware builds tested
  (2.5.0.1 – 2.9.0.1) stop at the QMI capability request on these cards.
* Arista's normal boot path (`bootipq`) checks image signatures; plain `bootm`
  does not. The install therefore sets its own U-Boot `bootcmd`, which loads
  the kernel from OpenWrt's UBI and falls back to Arista's boot if that fails.

## You need

* The console cable: RJ-45 rollover (RS-232, not TTL) to the C-360's console
  port, 115200 8N1, no flow control. A standard Cisco/switch console cable gives
  garbage on this port.
* For section A: a USB stick of 4 GB or more, Rufus, and Python 3 with
  pyserial (`pip install pyserial`) for `c360-flash.py`.
* For section B: a TFTP server reachable on the AP's untagged network.

## A. From a USB stick (the quick way)

### A1. Make the stick, once

Write `c360-openwrt-installer-<build>.img` (or the smaller `.img.xz`; Rufus
reads it directly) to the stick with Rufus: pick the stick under *Device*,
choose the image with *SELECT*, then *START*. Rufus recognises it as a disk
image and writes it as is (DD mode). Check the download against the
`.sha256` beside it first.

The stick then has one 2 GiB FAT32 partition, `C360OPENWRT`, with `c360/`:
the RAM installer, `factory.ubi`, their checksums and a README. Whatever is
left of a bigger stick stays unused.

`./build.sh c360` makes it with every build (`out/c360/<version>/`). From
images you already have:

```
python c360/tools/c360-make-stick.py --images <dir with the images> --img c360-openwrt-installer.img --xz
```

`--size-mib` changes the size from 2048. `c360-make-stick.py --images <dir> E:\`
instead copies the same files onto a stick that is already FAT32.

### A2. Install, per unit

Put the stick in the AP's USB port and the console cable on the PC, then:

```
python c360/tools/c360-flash.py --port COM6
```

Power the AP on (or power-cycle it) when it says so. It stops U-Boot, boots the
RAM installer from the stick (nothing in the U-Boot environment is saved),
and runs `arista-c360-install`, which:

1. **checks**: a C-360; running from RAM; the expected flash layout;
   `factory.ubi` against its checksum; slot 1 holds Arista's root filesystem
   with the five Wi-Fi firmware and board files the first boot copies, and
   NOR `0:HLOS_1` holds slot 1's kernel (the fallback). It prints slot 1's
   QCN9074 firmware version and warns if it is not WLAN.HK.2.5.r4.
   OpenWrt always replaces slot 0 and always keeps slot 1. If Arista calls
   slot 0 its primary (`pri=0`, after Arista upgraded itself into slot 0)
   that is only a warning, since slot 1's Arista is the one kept;
2. **backs up** every flash partition, gzipped, to
   `c360/backup-<MAC>-<time>/` on the stick (about 180 MiB per unit), each
   checked against the flash. **Keep these**: the ART partition holds that
   unit's radio calibration and MACs and exists nowhere else;
3. asks for the last four hex digits of the unit's MAC (unless `--yes`);
4. writes `factory.ubi` to slot 0 and reads the kernel and rootfs back;
5. sets the U-Boot boot command and `pri=1` in one environment write, so the
   fallback (`run ubootscript`) boots slot 1's Arista.

Then it reboots the AP and confirms OpenWrt starts from NAND.
`--dry-run` stops after the backup and writes nothing.

A 2 GiB stick holds about eleven units' backups; copy them off and delete
them from the stick when it fills.

Without `c360-flash.py`, the same by hand is in `c360/README.txt` on the stick:
stop U-Boot (B1), paste its one U-Boot line, then run `arista-c360-install`.

## B. By hand over TFTP

### B1. Stop U-Boot

U-Boot waits 2 s and only stops for a key string, compiled into Arista's
U-Boot (`0:APPSBL`, built May 20 2024):

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Paste it repeatedly while the AP boots until you see `IPQ807x#`. **Do not let
Arista's firmware boot by accident while experimenting**: its boot script runs
`saveenv` every time.

### B2. Boot the OpenWrt installer from RAM

At `IPQ807x#` (nothing below is saved; `saveenv` is never used here):

```
setenv ipaddr <AP address>
setenv serverip <TFTP server>
setenv fdt_high 0x4A3E0000
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat
tftpboot 0xA0000000 openwrt-qualcommax-ipq807x-arista_c360-initramfs-uImage.itb
bootm 0xA0000000#config@1
```

`panic=0` makes a crashing installer halt instead of rebooting: a reboot
without someone stopping U-Boot boots Arista, whose script saves the U-Boot
environment.

### B3. Back up the flash (strongly recommended)

The installer sees all partitions; only `ubi` (NAND slot 0) and `0:APPSBLENV`
are writable. From a PC:

```
for n in $(ssh root@<AP> "cut -d: -f1 /proc/mtd | grep mtd"); do
  ssh root@<AP> "cat /dev/$n" > c360-$n.bin
done
ssh root@<AP> cat /proc/mtd > c360-proc-mtd.txt
```

Check hashes (`sha256sum /dev/mtdN` on the AP against the copies).

### B4. Write OpenWrt to NAND slot 0 *(verified on one unit, 2026-10-07)*

```
scp …-squashfs-factory.ubi root@<AP>:/tmp/factory.ubi
ssh root@<AP>
  M=$(grep '"ubi"' /proc/mtd | cut -d: -f1)
  ubidetach -p /dev/$M 2>/dev/null
  ubiformat /dev/$M -y -f /tmp/factory.ubi
```

### B5. Set the boot command

From the installer, one U-Boot environment write. (Verified on one unit on
2026-10-07 as three separate `fw_setenv` calls, without `pri`; this
single-write form with `pri 1` is what `arista-c360-install` does and has not
yet been run on a unit.)

```
fw_setenv -s - <<'EOF'
owrt_args console=ttyMSM0,115200n8 ubi.mtd=ubi rootwait panic=10 pcie_ports=compat
owrt_boot setenv fdt_high 0x4A3E0000; setenv mtdids nand0=nand0; setenv mtdparts mtdparts=nand0:0x18000000@0x0(ubi); ubi part ubi && ubi read 0x44000000 kernel && bootm 0x44000000#config@1
bootcmd setenv bootargs ${owrt_args}; run owrt_boot; run ubootscript
pri 1
EOF
reboot
```

`fdt_high 0x4A3E0000` matters: Arista's default 0x4A400000 places the device
tree on top of U-Boot's own control DTB. `pri 1` makes the fallback boot slot
1. To boot Arista's firmware once: stop U-Boot and `run ubootscript`. To go
back to Arista permanently: `fw_setenv bootcmd 'run ubootscript'`.

### Keeping your settings across the install (optional)

`sysupgrade -b` refuses to run from the RAM installer. To carry settings
(e.g. a management VLAN) into the first boot, put a tarball of the wanted
`/etc/config/*` files at the root of the `rootfs_data` volume as
`sysupgrade.tgz` after step B4; OpenWrt restores it on first boot:

```
ubiattach -p /dev/$M -d 0
mkdir -p /tmp/rd && mount -t ubifs ubi0:rootfs_data /tmp/rd
tar czf /tmp/rd/sysupgrade.tgz -C / etc/config/network etc/config/firewall
umount /tmp/rd && ubidetach -d 0
```

If you add an interface (e.g. a VLAN) for management, put it in a firewall
zone that accepts input (`lan`), or SSH will be refused.

## First boot

OpenWrt's usual defaults: LAN on the uplink port (eth0) at 192.168.1.1, Wi-Fi
off, no root password (set one). The first boot copies the Wi-Fi firmware from
the Arista slot and restarts the radios; `logread | grep arista-c360-wifi`
shows what happened. Later updates are ordinary `sysupgrade`s.

## Known limitations

* The nRF52833 BLE module runs Arista's firmware unchanged: Bluetooth LE only
  (the airscan BLE survey); no Zigbee or Thread.
