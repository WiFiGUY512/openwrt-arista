# OpenWrt on the Arista C-130: installing by hand

**Most installs do not need this page.** The network installer in
[INSTALL.md](INSTALL.md) does all of this from a PC, with no cable. This is
the console procedure: for an AP the installer cannot reach or log in to, or
to see every step.

Steps 1 and 2 were run from the console on a unit (2026-11-21). Steps 4 and
5 are the environment write and `sysupgrade` the network installer made when
it installed a unit (2026-11-16); they have not been typed at the console.

OpenWrt goes into NAND slot 0 (Arista's `rootfs` and `opt`, 64 MiB together,
as one UBI). Arista's system stays in slot 1 (`rootfs2`, `opt2`, and its
kernel in NOR) as the fallback, and U-Boot is given a boot command that tries
OpenWrt first. Installing is: boot OpenWrt's initramfs from RAM, back up the
flash, write one U-Boot environment change, then `sysupgrade -n`.

## You need

* **The console cable:** the RJ-45 port next to the USB port, Cisco pinout
  (an ordinary Cisco console cable), RS-232, 115200 8N1.
* **A TFTP server** on the PoE+ port's network.
* **The images,** from the newest build for the C-130 in
  [openwrt-arista-installer](https://github.com/WiFiGUY512/openwrt-arista-installer/releases)
  (its [STATUS.md](https://github.com/WiFiGUY512/openwrt-arista-installer/blob/main/STATUS.md)
  lists them), or from `main/build-main.sh ipq806x DIR`:
  `openwrt-ipq806x-generic-mojo_c-130-initramfs-fit-uImage.itb` for the TFTP
  server, and `openwrt-ipq806x-generic-mojo_c-130-squashfs-sysupgrade.bin`.

## 1. Stop U-Boot

Paste `s6.D5r4Gnb89ZEWSW6Kq.` over and over from power-on until the prompt
`(IPQ) #` shows. U-Boot waits `bootdelay` seconds (2 on the unit this was
done on, as Arista's firmware left it). Do not let Arista's firmware start
meanwhile: its boot saves the U-Boot environment every time.

## 2. Boot OpenWrt from RAM (nothing is written)

At `(IPQ) #` (`setenv` without `saveenv` changes nothing in flash):

```
setenv autoload no; dhcp
setenv serverip <TFTP server>
tftpboot 0x44000000 openwrt-ipq806x-generic-mojo_c-130-initramfs-fit-uImage.itb
bootm 0x44000000
```

`dhcp` gives U-Boot an address on the PoE+ port (or `setenv ipaddr <AP
address>` instead). The image's own configuration (`config@2`) and command
line are used. If U-Boot's network passes nothing (`dhcp` gets no answer,
`tftpboot` prints only `T`), and the AP was restarted from a running
OpenWrt, power it off and on (unplug PoE) and stop U-Boot again. On the
lab unit 2 of 8 such restarts left U-Boot's network dead, U-Boot's own
`reset` did not bring it back, and every cold start (3 of 3) worked. To
boot from the network, start the AP from power rather than from a running
OpenWrt. OpenWrt takes its address by DHCP on the PoE+ port; root logs
in without a password.

## 3. Back up

Copy every partition off the unit (`/proc/mtd`), with checksums: the NOR
partitions with `cat /dev/mtdN`, the NAND ones (`ubi`, which is still
Arista's slot 0 at this point, `rootfs2`, `opt2`) with `nanddump`. At least
`0:art`: it holds this unit's calibration and MACs and exists nowhere else.

## 4. The boot command (the one environment write)

```
fw_setenv -s - <<'EOF'
owrt_boot setenv mtdids nand0=nand0 && setenv mtdparts mtdparts=nand0:64m(ubi) && ubi part ubi && ubi read 0x44000000 kernel && bootm 0x44000000
arista_boot setenv mtdids; setenv mtdparts; if test ${pri} = 0; then setenv bootargs ${ba0}; else setenv bootargs ${ba1}; fi; run ubootscript
bootcmd run owrt_boot; run arista_boot
pri 1
EOF
```

`owrt_boot` reads OpenWrt's kernel volume from slot 0 and starts it. If that
fails, `arista_boot` runs Arista's own boot (`ubootscript`) of slot 1
(`pri 1`). Arista's other variables (`ba0`, `ba1`, `sr`, `rp`, `ps`, …) stay
as they are.

## 5. Install

Copy the sysupgrade image to `/tmp`, then:

```
sysupgrade -n /tmp/openwrt-ipq806x-generic-mojo_c-130-squashfs-sysupgrade.bin
```

It makes slot 0 one UBI (kernel, root, settings) and reboots into OpenWrt.
What to do after the first boot is in
[INSTALL.md](INSTALL.md#after-the-install).

## Back to Arista's firmware

From OpenWrt, the write the network installer makes, then `reboot`:

```
fw_setenv -s - <<EOF
bootcmd run ubootscript
pri 1
bootargs $(fw_printenv -n ba1)
owrt_boot
arista_boot
EOF
```

Arista's boot command again, slot 1 chosen, its boot arguments set (Arista's
boot only sets them when `pri` changes), and the two OpenWrt variables
removed (a name alone deletes it). Arista's copy in slot 1 starts, with its
own settings: if it refuses `config` / `config`, press the reset button once
it has finished starting. OpenWrt stays in slot 0 until something else is
written there. To have Arista in slot 0 again, write slot 0 back from your
backup.
