# OpenWrt on the Arista C-230: installing by hand

**Most installs do not need this page.** The network installer in
[INSTALL.md](INSTALL.md) does all of this from a PC, with no cable. This is
the console procedure behind it: for an AP the installer cannot reach or log
in to, or to see every step.

The steps are: stop the boot loader, start OpenWrt from memory over TFTP,
back up the flash, then let the RAM system's own installer write OpenWrt to
slot 0 and set the boot command once. Done this way on one unit.

A halfway route: do steps 1 and 2, then let the network installer do the rest
from your PC with `python arista-field.py --installer-at <the AP's address>`.

## What it changes

- OpenWrt goes into NAND slot 0. **Arista's system in slot 1 is kept**: it
  is the fallback, and OpenWrt takes the radio's board data from it.
- The U-Boot environment is written once, with a boot command that tries
  OpenWrt first and falls back to Arista's own boot.
- Nothing else is written: U-Boot, the boot chain, the ART partition
  (calibration and MAC addresses) and slot 1 stay as they are.
- Whatever Arista had in slot 0 is replaced. A C-230 may run Arista from
  slot 0 (`pri=0`); slot 1 holds Arista too, and the boot command makes it
  the fallback (`pri=1`). Take the backup in step 4.

## You need

- **Console cable:** an RJ-45 rollover cable (RS-232, Cisco style) to
  the AP's console port, a USB-to-RS-232 adapter, and a terminal (PuTTY,
  screen, minicom). 115200 8N1, no flow control.
- **TFTP server on your PC**, allowed through its firewall, serving
  `openwrt-qualcommax-ipq807x-arista_c-230-initramfs-uImage.itb`. On Windows,
  Tftpd64. On Linux, tftpd-hpa or dnsmasq. On macOS, the built-in tftpd.
- **The build's tag:** the newest build for the C-230 in
  [openwrt-arista-installer](https://github.com/WiFiGUY512/openwrt-arista-installer/releases)
  (its [STATUS.md](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/STATUS.md)
  lists them). Use the same build for every file. It is `<tag>` below.
- **Network:** the AP's Ethernet 1 (the PoE port) on the same network as
  the PC, untagged, with a DHCP server. Power by PoE (802.3at) or DC.
- **SSH/SCP client** on the PC (built into Windows 10/11, macOS and Linux).
- **Time:** about 20 minutes.

## 1. Stop U-Boot

Connect the console, then power the AP. Paste this string repeatedly
while it boots, until you see `IPQ807x#`:

```
s6.D5r4Gnb89ZEWSW6Kq.
```

Then press Ctrl-C once to clear what is left on the line.

Don't let Arista's firmware boot while you are at it: its boot saves the
U-Boot environment every time.

## 2. Boot the installer from RAM

At `IPQ807x#`, type these one line at a time. Long pasted lines can hang
Arista's U-Boot. Nothing here is saved.

- `ipaddr` is a free address on your network, for the AP.
- `serverip` is your PC's address.

```
setenv ipaddr 192.168.1.250
setenv serverip 192.168.1.10
setenv fdt_high 0x4A3E0000
setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0
tftpboot 0x60000000 openwrt-qualcommax-ipq807x-arista_c-230-initramfs-uImage.itb
bootm 0x60000000#config@ac02
```

OpenWrt starts from RAM in about 30 s; press Enter for a shell. There is
no root password. The RAM system takes an address by DHCP on Ethernet 1;
check it with:

```
cat /tmp/sysinfo/board_name          # arista,c-230
ip -4 addr show br-lan
```

The installer's device tree attaches slot 0 (Arista's UBI) as it boots; UBI
may move a few of its blocks (bit-flip scrubbing, as Arista's own boot does).

## 3. Wait for the clock

Wait a minute for the AP to set its clock over the internet. The downloads
in step 5 are HTTPS and fail with a wrong date.

## 4. Back up the flash

On the AP's console:

```
mkdir -p /tmp/backup && cd /tmp/backup
cat /proc/mtd > proc-mtd.txt
for n in $(grep -v '"rootfs' /proc/mtd | grep -o '^mtd[0-9]*'); do cat /dev/$n > $n.bin; done
gzip -c /dev/$(grep '"rootfs"' /proc/mtd | cut -d: -f1) > slot0-rootfs.bin.gz
sha256sum * > SHA256SUMS
du -sh .
```

That copies every NOR partition (ART included) and NAND slot 0, Arista's
slot that the install replaces. Then copy it to the PC:

```
scp -O -r root@<AP address>:/tmp/backup c230-backup
```

If your scp doesn't know `-O`, leave it out. Keep this backup: ART exists
nowhere else, and putting Arista's slot 0 back needs it. Then free the
AP's RAM:

```
rm -rf /tmp/backup
```

## 5. Get the image onto the AP

On the AP's console:

```
mkdir -p /tmp/c230 && cd /tmp/c230
wget -O factory.ubi https://github.com/WiFiGUY512/openwrt-arista-installer/releases/download/<tag>/openwrt-qualcommax-ipq807x-arista_c-230-squashfs-factory.ubi
wget -O SHA256SUMS https://github.com/WiFiGUY512/openwrt-arista-installer/releases/download/<tag>/c230-install-SHA256SUMS
```

Without internet, copy them from the PC instead, under those names:

```
scp -O openwrt-qualcommax-ipq807x-arista_c-230-squashfs-factory.ubi root@<AP address>:/tmp/c230/factory.ubi
scp -O c230-install-SHA256SUMS root@<AP address>:/tmp/c230/SHA256SUMS
```

Create `/tmp/c230` on the AP first.

## 6. Install

```
arista-c230-install --dry-run --no-backup --stick /tmp/c230
arista-c230-install --no-backup --stick /tmp/c230
```

- **The first command only checks:** that the unit is a C-230, the flash
  layout, Arista's system in slot 1, and the image's checksums.
- **The second installs:**
  1. It asks for the last four hex digits of the AP's MAC address (on its
     label).
  2. It writes the U-Boot environment.
  3. It writes slot 0 and reads it back.
  4. It ends with `C230-INSTALL-RESULT: OK installed`.

Then:

```
reboot
```

It takes about 30 s from U-Boot to the console. What to do after the first
boot is in [INSTALL.md](INSTALL.md#after-the-install).

## The boot command

For reference, what the installer writes (one `fw_setenv -s` write):

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

## Back to Arista's firmware

- **Once:** stop U-Boot and type `run arista_boot`. It boots Arista from
  slot 1 (and Arista's own boot then saves the environment).
- **For good:** from OpenWrt, run `fw_setenv bootcmd 'run ubootscript'`,
  then `reboot`.
