# OpenWrt on the Arista C-360 — installation

Status: the manual steps (TFTP, sections B1–B5) were run on two units
(2026-10-07 and 2026-10-13); on the second, `arista-c360-install` did the
backup and the writes from the RAM system, with the images copied to it. The
boot command in B5, with its fallback `arista_boot`, was run at U-Boot on a
unit in the form sent to OpenWrt, split into more variables (OpenWrt from
slot 0, and the fallback into Arista); the C-260 runs it as here. Units
installed with an earlier installer or guide have an earlier fallback (see
B5). The USB stick method (section A: U-Boot loading the installer from the
stick, and `c360-flash.py`) is built and checked in simulation, but **it has
not been run on a unit yet**.

## What you get

* OpenWrt on the IPQ8074 (2.4 + 5 GHz), the QCN9074 card (the 6 GHz
  serving radio) and the QCN9072 card (the 2.4/5/6 GHz multifunction radio,
  airscan).
* OpenWrt lives in NAND slot 0. **Arista's system in slot 1 is kept**: it is
  the fallback, and it is where OpenWrt gets the radios' firmware and board
  data from.
* The image contains no Arista or unit-specific files. When the radios first
  start, OpenWrt copies the Wi-Fi firmware and board files **unmodified from
  your unit's own Arista slot 1**; MAC addresses and calibration come from the
  unit's ART partition. If slot 1 is erased, none of the radios start: the
  board data of all three chips, and the QCN9074 firmware, come from it.

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

Write `c360-openwrt-installer.img` (or the smaller `.img.xz`; Rufus
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

> Arista's U-Boot leaves the USB port unpowered: its VBUS is gpio29, which
> Arista's system switches. So the first two U-Boot commands, here and in the
> stick's README line, drive that pin high (`mw.l 0x0101D004 0x2`,
> `mw.l 0x0101D000 0x201`), before `usb start`. Seen on a unit: with them,
> U-Boot finds the stick and loads an image from it; without them, it finds
> no storage.

1. **checks**: a C-360; running from RAM; the expected flash layout;
   `factory.ubi` against its checksum; slot 1 holds Arista's root filesystem
   with the QCN9074 firmware (`amss.bin`, `m3.bin`) and Arista's stock board
   files (`bdwlan.b290`, `.bab`, `.baa`), NOR `0:HLOS_1` holds slot 1's
   kernel, and the U-Boot environment has Arista's `ba0`, `ba1` and
   `ubootscript` (all three for the fallback). It prints slot 1's
   QCN9074 firmware version and warns if it is not WLAN.HK.2.5.r4.
   OpenWrt always replaces slot 0 and always keeps slot 1. If Arista calls
   slot 0 its primary (`pri=0`, after Arista upgraded itself into slot 0)
   that is only a warning, since slot 1's Arista is the one kept;
2. **backs up** every flash partition, gzipped, to
   `c360/backup-<MAC>-<time>/` on the stick (about 180 MiB per unit), each
   checked against the flash. **Keep these**: the ART partition holds that
   unit's radio calibration and MACs and exists nowhere else;
3. asks for the last four hex digits of the unit's MAC (unless `--yes`);
4. sets the U-Boot boot command (B5) and `pri=1` in one environment write,
   so the fallback (`arista_boot`) boots slot 1's Arista. This comes before
   slot 0 is written: stopped at any point from here, the unit boots slot 1;
5. writes `factory.ubi` to slot 0 and reads the kernel and rootfs back.

Then it reboots the AP and confirms OpenWrt starts from NAND.
`--dry-run` stops after the backup and writes nothing.

A 2 GiB stick holds about nine units' backups (the installer wants 512 MiB
free before each); copy them off and delete them from the stick when it
fills.

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

An OpenWrt main image (`arista_c-360`, board name `arista,c-360`) has one
configuration, `config@hk09`, and needs no `pcie_ports=compat`:

```
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0
tftpboot 0xA0000000 openwrt-qualcommax-ipq807x-arista_c-360-initramfs-uImage.itb
bootm 0xA0000000#config@hk09
```

Its device tree names NAND slot 0 `rootfs`, not `ubi`, and the partitions
`0:art`, `logging` and so on in lower case; below, read `"rootfs"` for `"ubi"`.

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

From the installer, one U-Boot environment write, the same one
`arista-c360-install` makes:

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

* `owrt_boot` boots OpenWrt from slot 0. `fdt_high 0x4A3E0000` matters:
  Arista's default 0x4A400000 places the device tree on top of U-Boot's own
  control DTB.
* `arista_boot` is Arista's own boot with Arista's settings put back first:
  its `bootkernel` sets `bootargs` only when `pri` changes and then saves the
  environment, so without this a fallback would boot, and save, OpenWrt's
  `bootargs`, `fdt_high` and partition table.
* `pri 1` makes Arista's boot use slot 1, the slot that is kept.

For an OpenWrt main image the write is this instead (what
`arista-c360-install` writes from main's RAM installer). The device tree adds
`ubi.mtd=rootfs` and the root itself; the boot is in parts, as on the units
moved to main:

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

To boot Arista's firmware once: stop U-Boot and `run arista_boot`. To go
back to Arista for good: `fw_setenv bootcmd 'run ubootscript'` from OpenWrt
(or `setenv bootcmd run ubootscript; saveenv` at U-Boot), then reboot.

**Units installed with an earlier installer or guide** have an earlier boot
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

The C-360's defaults: **Ethernet 1 is the uplink**, with no WAN. `br-lan`
holds Ethernet 1 only and **takes its address by DHCP**, so look for the AP
in your DHCP server's leases. It uses the unit's own MAC, the one on its
label.
- **Ethernet 2 is free**, in no bridge, so a second cable to the same switch
  makes no loop. `arista-c360-net` puts it on the LAN, on a VLAN or a VXLAN,
  or bonds both ports (README.md).
- **Wi-Fi is off** until you turn it on, and SSH and LuCI have no password:
  set one first.
- **Failsafe mode** is at 192.168.1.1, as on any OpenWrt device. Enter it
  from the serial console: press `f` and Enter when the boot offers it.
- **The reset pinhole:** a short press reboots (tested on a unit). As on any
  OpenWrt device, a press of 5 s or more resets the configuration.

On the first boot, and the first after each `sysupgrade`, the radios take the
Wi-Fi firmware and board data from the Arista slot as they start; nothing is
restarted. If that fails, `logread` shows `ath11k-vendor-firmware` or
`arista-c360-board-data`. Later updates are ordinary `sysupgrade`s, which keep
the settings.

**Set the Wi-Fi country, then reboot once.** The board data is chosen by the
wireless country's group, and a fresh install has no country yet, so it
starts with FCC_CE's. When the country is set, its group's files are copied
in; the radios read them from the next boot.

## Known limitations

* The nRF52833 BLE module runs Arista's firmware unchanged: Bluetooth LE only
  (the airscan BLE survey); no Zigbee or Thread.
