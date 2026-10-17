# Arista W-318: hardware

What the port is built on: read from a unit (its console, Arista's device
tree as U-Boot prints it, Arista's own system read from its slots, and
OpenWrt booted from RAM), Arista's datasheet and the FCC photos.

## The board

- **SoC:** Qualcomm IPQ6010 (SoC version 1.0) on Qualcomm's IPQ6018
  AP-CP01-C3 reference design, machid 0x8030002: the same reference as
  OpenWrt's Cambium XE3-4. OpenWrt target qualcommax/ipq60xx.
- **RAM:** 2 GiB (U-Boot fixes up the 1 GiB in Arista's tree).
- **Flash:** 32 MiB SPI NOR (MX25U25635F) and a 3.7 GiB eMMC (Kioxia, GPT).
- **Console:** RJ-45, 115200 8N1, blsp1_uart3 (`ttyMSM0`).
- **PMIC** MP5496, **PoE PD** TI TPS23730 (802.3bt), a PoE PSE on Network 1.

## Flash layout

SPI NOR, Qualcomm's layout:

| Offset | Size | Partition |
|---|---|---|
| 0x000000 | 768 KiB | 0:SBL1 |
| 0x0c0000 | 64 KiB | 0:MIBIB |
| 0x0d0000 | 128 KiB | 0:BOOTCONFIG, 0:BOOTCONFIG1 (0x0f0000) |
| 0x110000 | 1.6 MiB | 0:QSEE, 0:QSEE_1 (0x2b0000) |
| 0x450000 | 64 KiB | 0:DEVCFG, 0:DEVCFG_1 (0x460000) |
| 0x470000 | 256 KiB | 0:RPM, 0:RPM_1 (0x4b0000) |
| 0x4f0000 | 64 KiB | 0:CDT, 0:CDT_1 (0x500000) |
| 0x510000 | 64 KiB | 0:APPSBLENV: U-Boot's environment |
| 0x520000 | 1 MiB | 0:APPSBL, 0:APPSBL_1 (0x620000): U-Boot |
| 0x720000 | 512 KiB | 0:ART |
| 0x7a0000 | 8 MiB | 0:HLOS: slot 0's kernel |
| 0xfa0000 | 8 MiB | 0:HLOS_1: slot 1's kernel |
| 0x17a0000 | 4 MiB | CONFIG |
| 0x1ba0000 | 128 KiB | DEVCERT |
| 0x1bc0000 | 2.1 MiB | SYS_DATA |
| 0x1de0000 | 2.1 MiB | RESERVED |

eMMC (GPT): p1 `rootfs` and p2 `rootfs_1` (128 MiB each: slot 0's and slot
1's squashfs), p3 `rootfs_data` and p4 `rootfs_data_1` (256 MiB each, ext4),
p5 `panicdump`, p6 `ramdump` (about 2.9 GiB). Arista's squashfs is xz with
options the kernel won't mount; `unsquashfs` reads it.

## U-Boot

- U-Boot 2016.01 (Arista's, 2023), "Secure boot: enabled", yet `bootm` of an
  unsigned FIT works. It stops at `IPQ6018#` on the same key string as the
  C-360's.
- `bootcmd` resets one variable (`env default default_env_version`) and runs
  `ubootscriptv2`, which saves the environment on every boot (its `sr`/`rp`
  counters) and runs `bootipq`; a `bootcmd` of one's own persists. `pri` 0
  is slot 0 (`0:HLOS` and p1), 1 slot 1 (`0:HLOS_1` and p2); the counters
  switch `pri` after boots that fail. `fdt_high` 0x48500000.
- The RAM boot: `tftpboot 0x60000000 <initramfs>`, `bootm
  0x60000000#config@cp01-c3` (INSTALL.md).

## Ethernet

- The IPQ6018's switch: port 5 (UNIPHY 1, SGMII+) to a QCA8081 2.5 GbE PHY at
  MDIO 24, the uplink with PoE in; ports 2, 3 and 4 (UNIPHY 0, PSGMII) to a
  QCA8075 at MDIO 1, 2 and 3. PHY resets gpio75 (QCA8075) and gpio77
  (QCA8081). Network 1 to 3 are 1 GbE.
- The panel numbers the LAN ports the other way round from the PHYs:
  Network 1 is PHY 3 (`dp4`), Network 3 PHY 1 (`dp2`) (a link test on a unit).
- MACs in 0:ART: 0x0 the base (the uplink, the label MAC), 0x6, 0xc and 0x12
  the three below it (`dp2`, `dp3`, `dp4`), the same as U-Boot's `ethaddr` to
  `eth3addr`; 0x40 the BLE module's (base minus 4); 0x50 the model string.

## Radios

- **2.4 and 5 GHz:** the IPQ6010's own (ath11k AHB, QCN5121/QCN5152 RF);
  OpenWrt's IPQ6018 firmware (WLAN.HK.2.5.0.1) runs them.
- **6 GHz:** a QCN9072 on pcie0 (reset gpio60), ath11k's QCN9074, PCIe Gen 3
  x1. Like the C-360's cards it runs Arista's build of the firmware,
  WLAN.HK.2.5.r4-00683 (`lib/firmware/IPQ6018/WIFI_FW/qcn9000/` in Arista's
  system); `12-ath11k-vendor-firmware` copies amss.bin and m3.bin from
  eMMC slot 1 when ath11k first asks for them. Public firmware not tried.
- **Calibration:** 0:ART at 0x1000 (64 KiB, the IPQ6010) and 0x26800
  (128 KiB, the card), as Arista's `read_caldata_to_fs.sh`; each carries its
  radios' MACs.
- **Board data:** Arista keeps a set per country group in
  `/lib/boarddata/radio12/<group>/bdwlan.b13` (the IPQ6010) and
  `/lib/boarddata/radio3/bdwlan.ba7` (the card; its own file for KCC, BZ,
  SA_SG_JM and JP), and copies the matching set in at boot (`link_board_data`
  in its `/etc/country_map.cfg`). `13-arista-w318-board-data` takes the same
  files from slot 1, the group from the wireless country (FCC_CE where a
  country has none of its own, as Arista; Arista then also turns its 6 GHz
  radio off, OpenWrt leaves that to the regulatory database), and
  `/etc/init.d/arista-w318-board-data` follows changes of the country. Both
  Arista slots carry the same radio files.
- No scan radio: Arista scans with the access radios.

## Bluetooth, TPM, USB

- **Bluetooth:** an nRF52833 on blsp1_uart2 (`ttyMSM1`, gpio69-72, four
  wires) running Arista's Zephyr HCI firmware, H4 at 115200 without flow
  control, as Arista attaches it. Reset gpio42 (active low; held high). gpio69,
  a flow-control line, is the bootloader's strap, used only for the module's
  firmware updates. No public address: a static random one from ART 0x40.
- **TPM:** TPM 2.0 (TIS over SPI) on blsp1_spi5 (gpio55-58), 500 kHz as in
  Arista's tree.
- **USB:** one USB 3.0 port on the SoC's controller; its power (VBUS) is cut
  by gpio73 low (Arista's `usb_ctrl_func`).

## LEDs and the button

Nine GPIO LEDs, active high, named by an LED walk on a unit:

| GPIO | Arista's name | Panel | OpenWrt |
|---|---|---|---|
| 18 | pwr | Power, green | `green:power`: running |
| 43 | conf | Power, amber | `amber:power`: boot, failsafe, upgrade |
| 24 | lan1-g | Uplink, green | `green:uplink`: a 2.5 Gb/s link |
| 25 | lan1-o | Uplink, orange | `orange:uplink`: 1 Gb/s or slower |
| 29 | 2g | Wi-Fi 2.4 GHz | `green:wlan-2ghz`: the radio on |
| 33 | 5g | Wi-Fi 5 GHz | `green:wlan-5ghz` |
| 36 | 6g | Wi-Fi 6 GHz | `green:wlan-6ghz` |
| 30 | lan2-g | Network 1/2/3, green | `green:lan`: a 1 Gb/s link on any |
| 31 | lan2-o | Network 1/2/3, amber | `amber:lan`: only slower links |

The one button outside is gpio23, low while pressed (Arista's tree calls it
`wps`); OpenWrt makes it `reset`. Arista's tree also has a `reset` (a power
key) at gpio19, which no button outside drives.

## PoE

- **In (the uplink):** the PoE controller reports the class on gpio9 and
  gpio53: 1 1 for 802.3af, 0 1 for 802.3at, 1 0 for 802.3bt (a unit on an
  802.3bt switch port read 1 0). gpio35 is 0 with a DC supply.
- **Out (Network 1):** a PSE enabled by gpio48 low, on Arista's system only
  on 802.3bt (`enable_pse_functionality`), as the datasheet: off on 802.3at
  and on the 12 V supply.
- Arista's policy (`/sbin/ap_power.sh`, `/etc/poe_prof.cfg`): on 802.3at
  without DC it caps the radios' power limit (2.4 GHz 19 to 18 dBm, 5 and
  6 GHz 20 to 17 dBm), cuts USB power and keeps the PSE off; chains and
  Bluetooth stay. The power a switch allocates by LLDP overrides the pins
  (38.1 W and up 802.3bt, 25 W and up 802.3at). `arista-w318-power` does the
  same.

## How OpenWrt is installed

OpenWrt takes Arista's slot 0 whole, slot 1 staying Arista's, the fallback:
the kernel FIT (about 5.7 MB) in NOR `0:HLOS`, the squashfs in p1 `rootfs`,
the overlay on p3 `rootfs_data` (OpenWrt's fstools finds it by name on the
root's disk and makes it f2fs at the first boot; the installer wipes its
start first, or Arista's ext4 would be mounted as it is).

- **U-Boot, one environment write** (`arista-w318-install`): `owrt_boot`
  reads `0:HLOS` (`sf read 0x60000000 0x7a0000 0x800000`) and boots it with
  root=/dev/mmcblk0p1; `arista_boot` puts Arista's `bootargs` back, sets
  `pri=1` and `sr=0`, and runs Arista's own boot command (whose `saveenv`
  must not keep OpenWrt's settings, and whose retry counter must not switch
  to slot 0); `bootcmd` runs the one, then the other; `pri=1`. Arista's
  `bootcmd` resets only `default_env_version` each boot, so this one stays.
  Arista's `bootipq` takes the slot from `pri` (`0:HLOS_1` and `rootfs_1`
  for 1) and checks its signature, which OpenWrt's kernel lacks: hence the
  boot of its own.
- **sysupgrade** (platform.sh): `0:HLOS` erased, the squashfs written to
  `rootfs`, the kernel written to `0:HLOS` last, the settings into
  `rootfs_data` (emmc_copy_config). OpenWrt's `mtd` tool reads `0:HLOS` as two
  devices ("0" and "HLOS"), so the partition goes by its `/dev/mtdN` path.
- At the first boot, `mkfs.f2fs` discards all of `rootfs_data`, and the eMMC
  took longer than the kernel waits: `mmc_erase: erase error -110` and
  `cache flush error -110` once, then the f2fs mounted and worked; not seen
  again in later boots.
