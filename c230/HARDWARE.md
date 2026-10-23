# Arista C-230: hardware

What the unit showed (U-Boot, Arista's own device tree `fdt@ac02`, Arista's
system) on 2026-10-22, MAC 30:86:2d:73:b6:6f.

## SoC, memory, flash

- Qualcomm IPQ8071A (the IPQ8074 die, AC02 reference design; U-Boot machid
  0x0801000a, its FIT configuration `config@ac02`), 1 GiB DDR4.
- SPI NOR MX25U25635F, 32 MiB: the C-260's layout up to `LOGGING`, then
  `DEVCERT` (0x1c50000, 128 KiB) and `RESERVED` (0x1c70000). Kernels in NOR,
  `0:HLOS` (0x750000) and `0:HLOS_1` (0xf50000), 8 MiB each; ART at
  0x690000; the AQR114C's firmware in `0:ETHPHYFW` (0x6d0000).
- NAND MX30UF4G18AB, 512 MiB, 128 KiB blocks: `rootfs` (slot 0) and
  `rootfs_1` (slot 1), 256 MiB each, UBI.
- ART: MACs at 0x0 (lan1, the label MAC) and 0x18 (lan2, label - 1); the
  rest of 0x0-0x1e are the reference design's 00:03:7f placeholders. The
  IPQ8074's calibration at 0x1000 (128 KiB), the QCA9882's at 0x33000 (2116
  bytes).

## Boot

- U-Boot 2016.01 (Feb 17 2020), secure boot (signed images up to U-Boot; it
  boots unsigned FITs). It waits 2 s and stops only for
  `s6.D5r4Gnb89ZEWSW6Kq.`, as the C-360, C-260 and W-318.
- Arista's environment is the C-260's: `bootcmd=run ubootscript`, slots by
  `pri`, and `bootkernel` saves the environment on every boot.
- `0:APPSBL_1` holds another U-Boot build (Feb 18 2020) without that key
  string; BOOTCONFIG keeps every slot on the primary.

## Radios

- IPQ8074: 5 GHz 4x4 (Arista's chainmask 0xf0) and 2.4 GHz 2x2 (0x3).
  Board data: Arista's `/lib/boarddata/bdwlan{,_AU,_BZ,_IC}.bin` by country
  group (`EXT_*` for the C-230E); Arista's tree gives board_id 0x292, ath11k
  reads qmi-board-id 255.
- QCA9882 (`168c:003c`) on PCIe 0 (`pci@20000000`), PERST GPIO 58, Gen 1 x1.

## Ethernet

- lan1: Aquantia AQR114C at MDIO 8, switch port 5, USXGMII on uniphy1; reset
  GPIO 44 (not to be used by Linux: it loses the firmware U-Boot loaded).
- lan2: Atheros AR8033 at MDIO 2, switch port 1, SGMII on uniphy0; reset GPIO
  25.

## Bluetooth: CSR8811

On `blsp1_uart3` (GPIO 46-49, RTS/CTS); its enable is GPIO 51 (Arista's
`ble_ctrl_func`). The C-260's PS keys file works. Arista's C-230 system of
2020 never starts it.

## LEDs

Two 74LV164 shift registers on GPIO 18 (clock), 19 (data), 20 (enable), as
the C-260: Arista's `ledc` indices and LED tables are the C-260's. Outputs:
power 12 green / 13 orange (13 is lit by U-Boot), LAN1 2/3, LAN2 0/1, the
third radio 4/5, 5 GHz 8/9, 2.4 GHz 10/11 (green/orange).

## Other

- Reset button: GPIO 52, active low.
- TPM: Infineon SLB9670 on QUP6 as SPI (0x78ba000, GPIO 0/2/9/16); held in
  reset while GPIO 62 is low (pulled down), released by Arista's `tpm2_init`.
- USB 2.0 on `usb_0`.
- Power source: GPIO 54 is 1 on 802.3af and 0 on 802.3at; GPIO 64 is 0 with a
  DC supply.
