# Arista C-360: hardware

What the hardware is, as found while bringing OpenWrt up on it. The device
tree (`files/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/arista_c360.dts`)
has the detail, with comments saying how each part was worked out.

## SoC, memory, flash

- **Qualcomm IPQ8074A, 2 GiB RAM.** Arista's own device tree calls it the
  `IPQ807x/AP-HK09` reference design.
- **32 MiB SPI NOR**, Qualcomm's usual layout:
  - the boot chain: SBL1, QSEE, DEVCFG, RPM and CDT, in pairs;
  - `0:APPSBL`: U-Boot. `0:APPSBLENV`: its environment (64 KiB, at 0x0);
  - `0:ART`: the unit's radio calibration and MAC addresses. It exists
    nowhere else, so back it up;
  - `0:ETHPHYFW`: the Ethernet PHY's firmware;
  - `0:HLOS` and `0:HLOS_1`: Arista's two kernels;
  - `CONFIG`, `DEVCERT` and two reserved partitions.
- **1 GiB NAND** (8-bit ECC; 4-bit reads it wrong):

  | Offset | Size | Arista's name | Use |
  |---|---|---|---|
  | 0x00000000 | 384 MiB | `rootfs` (slot 0) | OpenWrt (`ubi`) |
  | 0x18000000 | 384 MiB | `rootfs_1` (slot 1) | Arista, kept |
  | 0x30000000 | 256 MiB | `LOGGING` | untouched |

## Boot

- **U-Boot 2016.01**, built May 20 2024. It waits 2 s and stops only for a key
  string (INSTALL.md).
- **Its default boot writes the environment every time:** `bootkernel` ends
  in `saveenv; bootipq`.
- **Arista boots one of two slots, chosen by `pri`:**
  - `pri=0`: kernel `0:HLOS`, root NAND slot 0;
  - `pri=1`: kernel `0:HLOS_1`, root slot 1.
  - The counters `sr`/`rp` switch `pri` after boots that fail.
- **`bootipq` checks signatures** (signed MBN images, id 0x17, with the
  kernel FIT at 0x28).
- **OpenWrt's boot is its own `bootcmd`:** U-Boot's `ubi` commands read
  OpenWrt's kernel volume from slot 0, then `bootm`. If that fails, Arista's
  own boot runs (`run ubootscript`), and the installer sets `pri=1`, so that
  is slot 1.
- **`fdt_high 0x4A3E0000` is needed:** Arista's 0x4A400000 puts the device
  tree on top of U-Boot's own.
- **Console:** RJ-45, RS-232 levels, 115200 8N1, no flow control.
  Linux's console is `blsp1_uart5` (ttyMSM0).

## Radios

| Radio | Chip | Where | Bands | Use | Calibration (ART) |
|---|---|---|---|---|---|
| radio1 | IPQ8074 | `c000000.wifi` (AHB) | 2.4 GHz | serving | 0x1000 |
| radio0 | IPQ8074 | `c000000.wifi` (AHB) | 5 GHz | serving | 0x1000 |
| radio3 | QCN9074 | PCIe `0000:01:00.0` | 6 GHz | serving | 0x26800 |
| radio2 | QCN9074 | PCIe `0001:01:00.0` | 2.4/5/6 GHz | scan radio (airscan) | 0x4c000 |

The IPQ8074's two radios share one calibration area. Each area is 0x20000 bytes.

- **The QCN9074s only run Arista's build of Qualcomm's firmware,**
  `WLAN.HK.2.5.r4-00683` (amss.bin and m3.bin, in Arista's
  `/lib/firmware/IPQ8074/WIFI_FW/qcn9000/`). Every public build tested,
  2.5.0.1 to 2.9.0.1, stops at the QMI capability request.
- **Board files come from the same place:** `bdwlan.bab` for the card on
  pcie0 and `bdwlan.baa` for pcie1, with calibration variants
  `Arista-C360-pcie0`/`-pcie1`. The IPQ8074's is `bdwlan.b290`.
- **OpenWrt copies these five files from slot 1 at first boot**
  (`arista-c360-wifi-fw`), before the radios start.
- **The board reserves a fixed host-memory region for the cards.** ath11k
  must put the cards' calibration area (CALDB) and paged memory inside it
  (the two 99x ath11k patches).
- **`pcie_ports=compat`** keeps PCIe port services from taking interrupts, so
  both cards get their 16 MSI vectors.

## Ethernet

Two 10 GbE ports. Each has its own Aquantia AQR113C PHY (10GBASE-T, down to
5G, 2.5G, 1G and 100M) and its own Uniphy, connected over USXGMII:

| Port | Panel | PoE | Switch port | Uniphy | MDIO | MAC (ART) |
|---|---|---|---|---|---|---|
| eth0 | Ethernet 1 | in | 5 (`dp5_syn`) | 1 | 0x08 | 0x0 |
| eth1 | Ethernet 2 | in (seen once; to be confirmed) | 6 (`dp6_syn`) | 2 | 0x00 | 0x6 |

- **The PHY firmware:** Arista's U-Boot loads it into both PHYs at boot,
  from `0:ETHPHYFW` (`v5.5.6 Marvell Standard USX-All`). Each PHY then
  reports its temperature, which only the firmware provides.
- **USXGMII:** the PHYs talk USXGMII to the SoC. When a PHY reports it at
  link-up, the switch driver (qca-ssdk) sets its Uniphy to match. So even
  with `switch_mac_mode1`/`2` unset and the datapaths left at their default
  `sgmii`, eth0 linked at 10 Gb/s and passed traffic.
  - Arista's own device tree sets USXGMII from boot (`switch_mac_mode1`/`2`
    = `0x0d`, `MAC_MODE_USXGMII`).
  - Whether that is worth doing here is being evaluated: the first link
    after boot flaps once ("uniphy autoneg time out"), and throughput at 10G
    is not yet measured.

## Bluetooth LE: Nordic nRF52833

- **The link to the SoC:** HCI over UART on `blsp1_uart3` (0x78b1000, Linux
  `ttyMSM1`, pins gpio46-49), 115200 baud, **no flow control**
  (`btattach -N`).
- **Its control lines:**
  - reset on IPQ gpio37, held up by the `ble-nreset` hog;
  - gpio46 is also its bootloader strap.
- **Its static address** is in `0:ART` at 0x40.
- **Arista's firmware:**
  - a Zephyr 2.7.0 `hci_uart` controller (manufacturer 0x05F1), Bluetooth 5.3,
    LE only;
  - built for Nordic's PCA10100 board;
  - behind MCUboot with an RSA-2048 signature.

  The chip's radio can also do 802.15.4 (Zigbee, Thread), but this firmware
  doesn't.
- **The chip's USB** is not on the SoC's USB controller.
- **BlueZ 5.83's `btmgmt` sends no command** without the patch in
  `feeds/packages/utils/bluez/patches/`: its mgmt socket is opened in a
  start-up hook that was never run.

## Other

- **Front-panel LEDs:** two 74LV164 shift registers on bit-banged SPI, 16
  outputs, active high. The mapping is in the device tree; the radio LEDs
  follow their radios' phys (`/etc/hotplug.d/ieee80211/12-arista-c360-leds`).
- **TPM 2.0:** TIS over SPI (`spi@78b8000`, `tpm_tis_spi`).
- **USB 3.0, Type-A:** `usb_0`, with one port and no hub. `usb_1` is unused,
  as in Arista's own device tree.
