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
- **OpenWrt copies these five files from slot 1 when ath11k first asks for
  them**, as firmware hotplug scripts: `12-ath11k-vendor-firmware` for
  amss.bin and m3.bin, `13-arista-c360-board-data` for the board data. The
  slot is attached read-only. The kernel won't mount Arista's squashfs (its
  xz options block is 12 bytes where the kernel expects 8), so `unsquashfs`
  reads it.
- **The board reserves a fixed host-memory region for each card**
  (`memory-region`). Arista's firmware asks only for what ath11k already
  places there. The public 2.9.x firmware also asks for a calibration area
  (CALDB) and paged memory, which ath11k leaves out. Placing them in the
  region (two patches, since dropped) didn't make that firmware work.
- **`pcie_ports=compat`** keeps PCIe port services from taking interrupts, so
  both cards get their 16 MSI vectors.

## Ethernet

Two 10 GbE ports, both of which can power the unit (PoE in). Each has its own
Aquantia AQR113C PHY (10GBASE-T, down to 5G, 2.5G, 1G and 100M) and its own
Uniphy, connected over USXGMII:

| Port | Panel | PoE | Switch port | Uniphy | MDIO | MAC (ART) |
|---|---|---|---|---|---|---|
| eth0 | Ethernet 1 | in | 5 (`dp5_syn`) | 1 | 0x08 | 0x0 |
| eth1 | Ethernet 2 | in | 6 (`dp6_syn`) | 2 | 0x00 | 0x6 |

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
- **TPM 2.0:** an Infineon SLB 9670, firmware 7.85 (`TPM2_GetCapability`:
  manufacturer `IFX`, vendor `SLB9670`). TIS over SPI (`spi@78b8000`,
  `tpm_tis_spi`), as `/dev/tpm0` and `/dev/tpmrm0`; it is the kernel's
  hardware random source.
  - Arista's U-Boot doesn't send it `TPM2_Startup`, so the kernel does, after
    "A TPM error (256)… starting up the TPM manually": harmless. Nor does it
    measure anything: the PCRs all read zero after boot.
  - **The factory identity**, which Arista provisions in every unit, in the
    TCG IDevID layout:

    | NV index | certificate | its key (persistent handle) |
    |---|---|---|
    | `0x01C90000` | RSA 2048 | `0x81020000`: signing and decryption, no fixed scheme |
    | `0x01C90001` | ECC P-256 | `0x81020001`: signing, no fixed scheme |
    | `0x01C90011` | ECC P-256 | `0x81020011`: restricted signing (attestation) |
    | | | `0x81030000`: restricted decryption (a storage parent) |

    - Subject `O=ARISTA, CN=<MAC>, description=C-360 access point,
      serialNumber=<MAC>`, issued by Arista's "WiFi-TPM-Authority" CA and
      valid for about ten years.
    - Infineon's endorsement-key certificates are at `0x01C00002` (RSA) and
      `0x01C0000A` (ECC).
    - The keys need no password, and the owner hierarchy has none.
  - **strongSwan's TPM plugin** offered no signature scheme for a key without
    a fixed one, as the identity keys are, so IKEv2 couldn't sign with them
    ("no common hash algorithm found to create signature").
    `patches/feeds/packages/0001-strongswan-tpm-plugin.patch` fixes that.
    - The SLB 9670 reports FIPS 140-2 mode (`TPM2_PT_MODES`), so its RSA-PSS
      salt is the hash's length; strongSwan reads the mode from the TPM.
- **The reset pinhole** is gpio42, low while pressed. Arista's device tree
  has it as a gpio-keys "wps" key with a pull-up.
- **The SoC is an IPQ8076A** (`/sys/devices/soc0/machine`). Its cpufreq driver,
  `qcom-cpufreq-nvmem`, matches the board's root compatible `qcom,ipq8074`.
  Arista's device tree has `qcom,ipq807x-hk09`, `qcom,ipq807x` instead, which
  leaves no cpufreq and the cores at 800 MHz.
- **USB 3.0, Type-A:** `usb_0`, with one port and no hub. `usb_1` is unused,
  as in Arista's own device tree.
  - Enabled on a unit (`usb_1`, `qusb_phy_1`, `ssphy_1`, OpenWrt main), it
    does not start: "QUSB2PHY pll lock failed", then the DWC3 core fails
    (-EBUSY). Its PHY seems unpowered or unclocked on this board, so nothing
    there can be reached; the nRF52833's own USB is not on it either.
  - **gpio29 switches the port's VBUS:** high on, low off. Arista's device
    tree has no VBUS control; its `/sbin/ap_power.sh` drives the pin
    (`USB_CTRL_GPIO_PIN=29` in `/etc/poe_prof.cfg`). With the pin left alone
    the port has no power and no device appears; driven high, a stick
    enumerated at once (SuperSpeed). The device tree makes it a fixed
    regulator, the USB PHY's supply.
- **PoE class, as Arista's system reads it** (`is_at`, `is_bt`, `is_af` in
  `/etc/poe_prof.cfg`):

  | input | pins | 802.3af | 802.3at | 802.3bt |
  |---|---|---|---|---|
  | PoE 1 (Ethernet 1) | gpio54, gpio55, gpio56 | 1 1 1 | 1 0 1 | 0 1 0 |
  | PoE 2 (Ethernet 2) | gpio2, gpio66, gpio27 | 1 1 1 | 1 0 1 | 0 1 0 |

  - gpio64 is the DC jack: 0 when a DC supply is present.
  - On 802.3at, Arista turns the USB port off and lowers the radios' chains
    and transmit power. OpenWrt does neither yet.
  - A unit on 802.3bt on both inputs read 0 1 0 on both groups, and gpio64 1
    (no DC supply).
