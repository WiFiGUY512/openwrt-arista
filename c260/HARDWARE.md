# Arista C-260: hardware

What the hardware is, as found while bringing OpenWrt up on it. The device
tree (`files/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/arista_c260.dts`)
has the detail. The C-260 is a generation before the C-360: same SoC family
and boot chain, different radios, half the RAM, a smaller NAND, no TPM.

## SoC, memory, flash

- **Qualcomm IPQ8078A, 1 GiB DDR4.** Arista's device tree calls it
  Qualcomm's `IPQ807x/AP-HK01-C1` reference design (machid 0x8010000).
- **32 MiB SPI NOR** (Macronix MX25U25635F), Qualcomm's usual layout:
  - the boot chain: SBL1, MIBIB, BOOTCONFIG, QSEE, DEVCFG, APDP, RPM and CDT,
    most in pairs;
  - `0:APPSBL` (and `_1`): U-Boot. `0:APPSBLENV` at 0x480000: its environment
    (64 KiB, one copy);
  - `0:ART` at 0x690000: the unit's radio calibration and MAC addresses. It
    exists nowhere else, so back it up;
  - `0:ETHPHYFW`: the Ethernet PHYs' firmware, which U-Boot loads;
  - `0:HLOS` and `0:HLOS_1`: Arista's two kernels (8 MiB each);
  - `CONFIG`, `LOGGING` and a reserved partition.
- **512 MiB NAND** (Macronix MX30UF4G18AB, 2 KiB pages, 128 KiB blocks):

  | Offset | Size | Arista's name | Use |
  |---|---|---|---|
  | 0x00000000 | 256 MiB | `rootfs` (slot 0) | OpenWrt (`ubi`) |
  | 0x10000000 | 256 MiB | `rootfs_1` (slot 1) | Arista, kept |

- **No TPM.** The C-360's TPM bus is disabled in Arista's C-260 device tree,
  and the pin the C-360 uses for it is the button here.

## Boot

- **U-Boot 2016.01**, built Feb 17 2020 (boot chain BOOT.BF.3.3.1-00147). It
  waits 2 s and stops only for a key string, the same as the C-360's.
- **No secure boot:** U-Boot prints no authentication lines, and `bootm`
  boots an unsigned FIT.
- **Its default boot writes the environment every time:** `bootkernel` ends
  in `saveenv; bootipq`, and it sets `bootargs` from `ba0`/`ba1` only when
  `pri` has changed since the last boot.
- **Arista boots one of two slots, chosen by `pri`:**
  - `pri=0`: kernel `0:HLOS`, root NAND slot 0 (`ba0`);
  - `pri=1`: kernel `0:HLOS_1`, root slot 1 (`ba1`).
  - The counters `sr`/`rp` switch `pri` after boots that fail.
- **OpenWrt's boot is its own `bootcmd`:** U-Boot's `ubi` commands read
  OpenWrt's kernel volume from slot 0, then `bootm`. If that fails, Arista's
  own boot runs, with Arista's `bootargs`, `fdt_high` and partition settings
  put back first (INSTALL.md).
- **`fdt_high 0x4A3E0000`** for OpenWrt, as on the C-360.
- **Console:** RJ-45, RS-232 levels, 115200 8N1, no flow control
  (`blsp1_uart5`).

## Radios

- **IPQ8074 (ath11k): 2.4 GHz and 5 GHz.** Calibration from ART 0x1000
  (128 KiB). Board data: Arista ships four, one per regulatory group
  (`/lib/boarddata/bdwlan.bin`, `_UK`, `_AU`, `_ICKR`) and copies the right
  one into place at every boot. OpenWrt copies the one for the configured
  country from the unit's slot 1 the first time the radio starts
  (`/etc/hotplug.d/firmware/13-arista-c260-board-data`). The public
  ath11k-firmware-ipq8074 runs it.
- **QCA988x (ath10k, 168c:003c): the third radio**, on PCIe 0 (Gen1 x1,
  reset gpio58). Arista uses it to scan. Calibration: ART 0x33000, 2116
  bytes, given to ath10k as an nvmem cell. The public ath10k-ct firmware runs
  it. Arista's device tree also describes QCN9000 cards; the C-260 has none.

## Ethernet

- **Two 5 GbE ports: Aquantia AQR114C PHYs** (ID 0x31c31c22) on MDIO
  addresses 8 and 0, switch ports 5 and 6, USXGMII. U-Boot loads their
  firmware from `0:ETHPHYFW`; Linux uses them as they are.
- **MACs:** ART 0x18 (port 5, `eth0`) and 0x1e (port 6, `eth1`), the
  offsets Arista's `/opt/sensor/env` names (`ETH0_MAC_OFFSET`,
  `ETH1_MAC_OFFSET`). The 0x18 one is Arista's base MAC. ART 0x0–0x12 hold
  Qualcomm's 00:03:7f placeholders, as U-Boot's `ethaddr` does.

## Bluetooth: CSR8811

- On `blsp1_uart3` (gpio46–49: TX, RX, CTS, RTS); enable (active high) on
  gpio51.
- ROM-based; it boots in BCSP at 115200. Arista loads its PS keys
  (`/sbin/csr8x11-a12-bt4.2-patch.psr`: ROM patches, H4 at 115200, the 26 MHz
  crystal, the BD address) with `bccmd psload -r`, then attaches it as H4.
  BlueZ no longer has `bccmd`; `arista-c260-bluetooth` does the same with the
  kernel's BCSP driver and `hcitool` vendor commands.
- **H4 needs RTS/CTS** on OpenWrt's kernel. Arista attaches with `noflow`;
  here the chip then never answers.
- BD address: Arista's base MAC less 2.

## LEDs

- Two chained 74LV164 shift registers on gpio18 (clock) and gpio19 (data),
  cleared by gpio20 (held high). Twelve of their sixteen outputs drive LEDs.
- Output = 15 − the index in Arista's `qcom,ledc_blink_indices`, the same
  rule as the C-360's. The power LED is outputs 12 and 13; U-Boot lights 13
  (`LED INIT with value 0x2000`). The others pair up: 8/9, 10/11, 4/5, 2/3
  and 0/1.

## Other

- **Button:** gpio52, active low (Arista's device tree calls it `wps`).
- **USB 3.0:** one port (`usb3@8A00000`).
- **PoE:** Arista reads the class it negotiated on each input from gpio54,
  55 and 56 (PoE 1), 2, 66 and 27 (PoE 2) and 64, and on 802.3af/at power it
  lowers transmit power, turns the third radio down and turns USB and
  Bluetooth off. OpenWrt does none of that.
