# Arista W-118 — hardware

Read from a unit (2026-10-19) unless marked: its console, U-Boot, a full
flash dump, Arista's device tree and system, and OpenWrt main from RAM.

## Board

| Part | What | Notes |
|---|---|---|
| SoC | Qualcomm IPQ4019, 4x Cortex-A7 | OpenWrt target `ipq40xx` (generic). QSDK board AP-DK04.1-C1, machid 0x8010001 |
| RAM | 512 MiB DDR3L | |
| NOR | 32 MiB, Macronix MX25L25635E | SPI; boot chain, U-Boot, its environment, ART, Arista's two kernels |
| NAND | 256 MiB SLC, Micron MT29F2G08ABAEA | 2 KiB pages, 128 KiB blocks; Arista uses the lower half |
| Radio 1 | IPQ4019 `wifi0`, 2.4 GHz 2x2 802.11n | ath10k (AHB) |
| Radio 2 | IPQ4019 `wifi1`, 5 GHz 2x2 802.11ac | ath10k (AHB) |
| Radio 3 | QCA9882 on PCIe, 2.4 or 5 GHz 2x2 802.11ac | ath10k (PCI), Arista's scanning radio |
| Ethernet | IPQ4019 switch, QCA8075 PHYs over PSGMII | uplink (PoE in) and LAN 1-3; LAN 3 can supply PoE |
| Bluetooth LE | NXP Kinetis controller, NXP's HCI firmware | UART, HCI 4.2, manufacturer 37 (NXP), public address `88:b1:e1:…` |
| Power | PoE (802.3af/at) on the uplink, or 12 V DC | |
| USB, TPM | none | |
| Console | internal 4-pin header J12, 3.3 V TTL | no console port outside |

## Console

J12 ("CPU"): pin 1 is 3.3 V (do not connect it), pin 2 GND, pins 3 and 4
the UART's TX and RX, 115200 8N1. Use a 3.3 V USB-TTL adapter. The cover
has to come off.

## U-Boot

- U-Boot 2012.07 (QSDK, 2018), prompt `(IPQ40xx) #`.
- **No countdown: any key stops it**, but only in the moment after the boot
  ROM's banner. Send keys from power-on.
- Arista's `bootcmd=run ubootscript` boots one of two slots by `pri`
  (`0:HLOS` with NAND `rootfs`, or `0:HLOS1` with `rootfs2`) and **saves the
  environment on every boot**: a boot counter (`sr`, `rp`) that falls back
  to the other slot after three failed boots.
- Its `bootipq` reads the slot `pri` names from NOR itself (after `sf
  probe`), and has **no LZMA** ("Unimplemented compression type 3"). A
  kernel for a stock slot must fit 5 MiB uncompressed in its FIT: OpenWrt's
  zImage FIT does (3.9 MB).
- After a warm reboot from OpenWrt, `bootipq` finds a "Crashdump magic" flag
  and resets once before it boots. OpenWrt's own boot command uses `bootm`
  and never meets it.
- No `boot` command: `run bootcmd`.

## Flash

NOR (U-Boot's SMEM table):

| Partition | Offset | Size | |
|---|---|---|---|
| 0:SBL1, 0:MIBIB, 0:QSEE, 0:CDT, 0:DDRPARAMS | 0x000000 | 0xe0000 | boot chain |
| 0:APPSBL | 0x0e0000 | 512 KiB | U-Boot |
| 0:APPSBLENV | 0x160000 | 64 KiB | U-Boot's environment (`fw_printenv`) |
| 0:ART | 0x170000 | 64 KiB | MACs and calibration, this unit's only copy |
| 0:HLOS | 0x180000 | 5 MiB | Arista's kernel, slot 0 |
| 0:HLOS1 | 0x680000 | 5 MiB | Arista's kernel, slot 1 (a copy of slot 0) |
| 0:UCONFIG | 0xb80000 | 4 MiB | Arista's configuration |
| (no name) | 0xf80000 | 16.5 MiB | not free: about 6 MiB of unknown data, then a JFFS2 |

NAND:

| Partition (OpenWrt) | Offset | Size | |
|---|---|---|---|
| `arista_rootfs` | 0x0000000 | 64 MiB | Arista's root, slot 0 (UBI) |
| `arista_rootfs2` | 0x4000000 | 64 MiB | Arista's root, slot 1 |
| `ubi` | 0x8000000 | 128 MiB | unused by Arista: OpenWrt's kernel, root and settings |

Arista's slots are not called `rootfs`, which OpenWrt would take as its own
root. Arista's own kernel has partitions for the lower half only.

## ART

| Offset | What |
|---|---|
| 0x0 | MAC `…:1f`: the uplink, the label MAC |
| 0x6 | MAC `…:1e`: the LAN ports (the label MAC - 1) |
| 0x1000 | IPQ4019 2.4 GHz pre-calibration (0x2f20) |
| 0x5000 | IPQ4019 5 GHz pre-calibration (0x2f20) |
| 0x9000 | QCA9882 calibration (0x844) |

The radios' MACs come from their calibration data.

## GPIOs

| GPIO | What |
|---|---|
| 49 | LED power (green, active low) |
| 41 | LED uplink |
| 23 | LED 2.4 GHz |
| 22 | LED 5 GHz |
| 32 | LED scanning radio |
| 10 | LED "Network 1/2/3", one for the three LAN ports (Arista calls it the PSE LED) |
| 18 | reset button, active low |
| 42 | Bluetooth controller reset, low resets |
| 28 | PoE output on LAN 3, high is on |
| 29 | PoE in is 802.3af (input) |
| 43 | DC power present (input) |
| 48 | PCIe PERST |
| 46 | PCIe WAKE |
| 47 | MDIO reset |

## Ports

| Panel | Switch port | OpenWrt |
|---|---|---|
| WAN | 5 (PHY 4) | `uplink` |
| LAN 1 | 2 (PHY 1) | `lan1` |
| LAN 2 | 3 (PHY 2) | `lan2` |
| LAN 3 | 4 (PHY 3) | `lan3` |

Switch port 1 is not wired. The two RJ-45 pass-through jacks are wired to
each other only.

## Radios' board data

Arista's system uses QSDK's DK04 board files for the IPQ4019
(`boarddata_0.bin` = DK04 2G, `boarddata_1.bin` = DK04 5G). They differ from
board-2.bin's generic entries for board ids 20 and 21 (1183 and 1957 bytes),
so OpenWrt carries them as the `Arista-W118` variant
(openwrt/firmware_qca-wireless#179).

## Bluetooth

The NXP controller is on `blsp1_uart2` (`/dev/ttyMSM1`), 115200 baud, H:4,
**no flow control**, reset on GPIO 42. Arista resets it and waits about 10 s
(its ROM bootloader holds the UART) before attaching, on every boot. Once,
the controller was found answering commands but reporting no LE
advertisements, and only that reset cleared it: the port does the same reset
at boot.
