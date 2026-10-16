# Arista C-360

A Wi-Fi 6E campus access point: a Qualcomm IPQ8076A (IPQ8074 family) with
its own 2.4 and 5 GHz radios, a QCN9074 card (the 6 GHz serving radio) and a
QCN9072 card (its 2x2 sibling, the 2.4/5/6 GHz scan radio), two 10 GbE ports
with PoE in, a Nordic nRF52833 Bluetooth LE controller, an Infineon TPM 2.0
and a USB 3.0 port. Details in [HARDWARE.md](HARDWARE.md); installing in
[INSTALL.md](INSTALL.md).

## What works

Seen working on a unit unless marked *(built, not yet on a unit)*.

- **All four radios.** radio0 (5 GHz) and radio1 (2.4 GHz) are on the
  IPQ8074, and radio3 (6 GHz) is on the QCN9074. radio2, on the QCN9072, is
  the scan radio and serves no clients (below).
- **Two radio plans, as on Arista's system** (`arista-c360-radio`): 6 GHz,
  the default, or dual 5 GHz (radio0 on lower 5 GHz, radio3 on upper 5 GHz).
  On a unit, both ways: in dual 5 GHz, radio0 has 5180-5320 MHz and radio3
  5500-5845 MHz; back in 6 GHz, both have their full bands again.
  `arista-c360-radio-mode dual5g && reboot` switches: it moves radio3 to
  5 GHz (channel auto) and keeps radio0 in the lower band, and the next boot
  brings the plan's gpio9 level, IPQ8074 calibration and board data for all
  three radios (HARDWARE.md). `arista-c360-radio-mode 6g` puts the radios'
  settings back, and `status` shows what runs.
  - Board data follows the wireless country, by Arista's country groups. After
    changing the country: `arista-c360-radio-mode apply`, then reboot.
- **Ethernet: two 10 GbE ports, both PoE in** (Aquantia AQR113C: 10G, 5G,
  2.5G, 1G, 100M). eth0 is Ethernet 1 and eth1 is Ethernet 2.
  - Both ports link at 10 Gb/s and at 2.5 Gb/s, and pass traffic both ways.
  - MACs and radio calibration are read from the unit's own ART partition.
  - Not yet measured: throughput at 10G.
- **Ethernet 1 is the uplink; there is no WAN.** On a fresh install `br-lan`
  holds Ethernet 1 only and takes its address by DHCP, so the port works as an
  access port, and as a trunk once VLANs are added on it. Ethernet 2 is free,
  in no bridge, so two cables to one switch make no loop.
- **Ethernet 2, or a bond, with `arista-c360-net`:**

  | command | what it does |
  |---|---|
  | `port2 lan` | Ethernet 2 on the LAN, with Ethernet 1 |
  | `port2 vlan 30` | Ethernet 2 an access port on VLAN 30, bridged to VLAN 30 on the uplink |
  | `port2 trunk 20 30` | the LAN untagged and VLANs 20 and 30 tagged, to chain another AP |
  | `port2 vxlan 100 <peer>` | Ethernet 2 bridged into a VXLAN tunnel (VNI 100) |
  | `port2 off` | Ethernet 2 back in no bridge |
  | `bond on` / `bond off` | both ports one LACP bond (802.3ad), and back; the uplink's VLANs move with it |
  | `status` | the uplink, the bridges and their ports |

  - A device on Ethernet 2 needs power of its own: both ports are PoE in only.
  - Each change is undone after 120 s unless `arista-c360-net confirm` follows,
    so a change that cuts the AP off reverts by itself.
  - Tested on a unit managed on a tagged VLAN, against an Arista switch with
    LACP fallback: `bond off`, `bond on` (both links in one aggregator),
    `port2 vxlan`, and, with Ethernet 2 unplugged so nothing could loop,
    `port2 vlan` and `port2 trunk`. A change left unconfirmed was undone by
    itself.
  - The bond is netifd's own bonding device (`bond0`), which sets 802.3ad as
    it creates the bond. The older proto-bonding interface could come up in
    balance-rr at boot, a VLAN of it in a bridge having raised the bond first
    (seen on a unit); `bond on` replaces such a config. Tested across a
    sysupgrade: 802.3ad, in one aggregator with the switch, at boot.
  - A port the bond releases stays down on OpenWrt 25.12 (the bonding driver
    closes it after netifd has raised it); the tool raises it again.
- **VXLAN:** netifd's `vxlan` protocol and `kmod-vxlan` are in the image.
  Tested on a unit: a netifd VXLAN tunnel bridged to Ethernet 2
  (`arista-c360-net port2 vxlan`), and the kernel's VXLAN between two network
  namespaces with a ping across the overlay.
- **Front-panel LEDs:** power, the three Wi-Fi bands, and both Ethernet
  ports in steady link-speed colours: green for a multi-gig link (2.5, 5 or
  10G), orange for 1G or slower. Green at 5 and 10G is *(built, not yet on a
  unit)*; before, it lit at 2.5G only.
- **Bluetooth LE:** the nRF52833 runs Arista's own firmware unchanged (a
  Zephyr HCI controller, Bluetooth 5.3, LE only), over a UART.
  - It comes up by itself at boot: powered, with the unit's static address,
    not advertising.
  - `btmgmt` works. BlueZ's daemon isn't in the image; add `bluez-daemon` for
    `bluetoothctl`.
- **The scan radio, airscan.** A service that only ever listens, and only on
  radio2, so the serving radios never scan or leave their channels. It runs:
  - a spectrum survey (ath11k spectral scan; 20 MHz windows on 2.4 and 5 GHz,
    80 MHz ones on 6 GHz with 40 MHz for channels 225-229 and 20 for 233;
    per window, the share of samples above -82 dBm per 20 MHz, +3 dB per
    doubling of its width);
  - a survey of every network on every 2.4, 5 and 6 GHz channel;
  - a survey of the clients on the channels that have networks, with those
    that connect to none (probing) counted apart, with their probe requests;
  - a Bluetooth LE survey, on the nRF52833.

  It never idles: between the periodic network surveys and spectrum sweeps
  it surveys clients.

  It detects:
  - wired rogues: a network relaying the AP's own wired ARP probes that isn't
    one of its own;
  - evil twins: one of its SSIDs on a network that never relays them;
  - its own BSSID heard where it isn't (not its own beacon heard off its
    channel, nor a channel it just moved from);
  - deauthentication floods.

  The wired probes go out on each of the AP's L2 domains (bridges, VLANs, a
  bond, never the bond's member ports), read again every round, so the probes
  follow network changes.
  - **In LuCI, Status > Air Scan** (`luci-app-airscan`): the spectrum (each
    channel's occupancy, the power density as a spectrum analyser shows it,
    and one channel's FFT), the channels and networks with the alerts, the
    clients (the probing ones apart), Bluetooth LE devices, and the settings.
    Seen on a unit.
  - Results also from `ubus call airscan status|spectrum|bss|clients|ble|events`,
    and JSON in `/tmp/airscan`.
  - **The radio can be lent.** `ubus call airscan lend '{"seconds":60,"to":"who"}'`
    gives it to another service for a while, a client test for one: airscan
    takes its own interfaces off it and runs no job on it until
    `ubus call airscan reclaim`, or until the loan runs out (300 s at the
    most), when it also removes what the borrower left. It answers no while
    it scans or sweeps. Its jobs keep their times, so a loan costs no scan or
    sweep. `status` lists what it can do in `features`.
  - **A deaf scan radio is brought back.** One that hears no network at all,
    where the last look heard some or the AP itself is on the air, has its
    driver bound again (`ath11k_pci`, about 20 s), and the next look says
    whether that worked: at most 6 times an hour, and not again for an hour
    after a try that did not. A look follows every sweep, and a whole round
    of client surveys with no beacon heard asks for one. `status` counts the
    tries in `heal`.
    - On 2026-10-11 this radio went deaf at the sweep after it had been a
      client on a DFS channel, six times of six, when airscan was stopped
      for the test and started again after it. Lent instead (2026-10-15),
      it joined on a DFS channel four times of four and heard as before at
      the next sweep. A borrower need not bind the driver again; a radio
      that does go deaf is still brought back as above. Why it went deaf
      isn't known.
  - Settings: `/etc/config/airscan`, or the LuCI page. List your own SSIDs in
    `trusted_ssid`, or your other APs show up as wired rogues.
- **Arista's PoE power policy** (`arista-c360-power`): on 802.3at (or af)
  power alone, with no DC supply or 802.3bt on the other input, the USB port
  is turned off and the serving radios' transmit power capped (15 dBm at
  2.4 GHz, 18 dBm at 5 and 6 GHz), as Arista's own system does. The PoE class
  comes from the PoE controller's pins (HARDWARE.md). `arista-c360-power
  status` shows the inputs and what is applied; `/etc/config/arista-c360-power`
  turns it off or changes the caps. Tested on a unit on 802.3bt (full power),
  and the 802.3at path with a test override.
  - The 2.4 GHz radio also drops from 4 chains to 2 (TX and RX mask 3), as on
    Arista's system. Chains can only change while a radio is down, so they go
    into that radio's `txantenna`/`rxantenna` in `/etc/config/wireless`, and
    Wi-Fi reloads that radio once.
  - The radio's own settings are saved and put back on full power, unless you
    changed the antennas in the meantime. A radio you set antennas for is left
    alone.
  - **LLDP:** `lldpd` runs on both Ethernet ports, sending and receiving LLDP
    only (CDP, FDP, EDP and SONMP off), so the switch sees the AP as a
    neighbor, with port IDs `eth0` and `eth1`. As on Arista's system, the
    power a switch reports allocating on a port overrides that input's pins
    when there's no DC supply. 38.1 W or more counts as 802.3bt, 25 W or more
    as 802.3at, and less as 802.3af.
    `arista-c360-power status` shows both readings. The AP sends no power
    request of its own, so the switch allocates by hardware class.
  - The policy is checked every 30 s, and a change applies after two readings
    in a row, so allocations that arrive late and supplies that change at
    runtime take effect.
  - Tested on a unit against an Arista switch that reports 40 W allocated on
    both ports (full power), and with an override reporting 25.5 W (802.3at:
    USB off, caps, 2 chains, back on the real reading).
- **TPM 2.0:** an Infineon SLB 9670 (firmware 7.85) on SPI (`tpm_tis_spi`).
  `/dev/tpm0` and the resource manager `/dev/tpmrm0` work, and the TPM is the
  kernel's hardware random source (`tpm-rng`).
  - `tpm2-tools` 5.8, on `tpm2-tss` 4.2, is in the image (OpenWrt 25.12
    packages neither): random numbers, keys, signing and verifying, sealing.
    Tested on a unit.
  - Each unit's factory identity, Arista's certificates in the TPM with their
    keys, reads out with `tpm2_nvread` (HARDWARE.md).
- **IPsec with the unit's TPM identity:** strongSwan with its TPM plugin
  (`strongswan-mod-tpm`, in the build's feed) authenticates IKEv2 with a
  factory certificate and its key, which never leaves the TPM. Tested on a
  unit: an IKEv2 exchange and an ESP tunnel, with the RSA identity and with
  the ECC one. Setup below.
- **CPU frequency scaling,** 1.0 to 2.2 GHz (`cpufreq-dt`, `schedutil`).
  Before, with the device tree's QSDK compatibles, the cores stayed at
  800 MHz.
- **The USB 3.0 port,** powered by gpio29 (a regulator in the device tree;
  Arista's system switches the same pin). Seen on a unit: a stick enumerates
  at boot (SuperSpeed). Arista's U-Boot leaves the port off, so the stick
  installer powers it first (INSTALL.md).
- **The reset button** (the pinhole): a short press reboots, as on any
  OpenWrt device, and a press of 5 s or more resets the configuration. The
  reboot was tested on a unit.
- **sysupgrade**, and **Arista's system kept as a fallback:** OpenWrt lives in
  NAND slot 0, and Arista's slot 1 is never written.

## What doesn't (yet)

- **Measured boot.** Arista's U-Boot doesn't extend the TPM's PCRs (all read
  zero after boot), so the TPM can't attest to what booted.
- **Zigbee and Thread.** The nRF52833's radio can do 802.15.4, but Arista's
  firmware is Bluetooth LE only, and signed.
- **The USB stick has not been used to install a unit yet** (INSTALL.md,
  section A: U-Boot loading the installer from it, and `c360-flash.py`). The
  manual install (section B) has, and `arista-c360-install` has, from the
  RAM system.

## Requirements

- **Arista's system in slot 1.** OpenWrt contains no Arista files. When the
  radios first start it copies the QCN9074 firmware and the board files,
  unmodified, from the unit's own Arista system in NAND slot 1 (firmware
  hotplug scripts, read-only).
  - Only Arista's build of that firmware (`WLAN.HK.2.5.r4`) runs these cards;
    every public `ath11k-firmware` build tested stops during start-up.
  - The installer checks slot 1 before writing anything.
- **No changes to ath11k.** Arista's firmware runs with OpenWrt's ath11k as
  it is. Two earlier patches, which put the cards' calibration area and paged
  memory in the board's fixed host-memory region, were only needed while
  trying the public firmware. Without them, a unit's four radios came up and
  scanned on both OpenWrt 25.12 and main (2026-10-08).

## Packages

The kernel is OpenWrt 25.12's, configured with `KERNEL_RELAY`, which the
spectrum survey needs. So OpenWrt's own kernel-module packages do not fit it,
and modules come from the feed each build makes (`out/c360/<version>/feed/`).
Other packages install from OpenWrt's 25.12 feeds as usual, except
strongSwan's TPM plugin, which is in the build's feed too.

## IPsec with the TPM identity

Arista gives every unit an identity in its TPM: certificates from Arista's
own CA, each with a key that the TPM holds and never releases (HARDWARE.md).
strongSwan can authenticate IKEv2 with one.

1. Add the build's feed to `/etc/apk/repositories.d/customfeeds.list` (its
   `packages/` and `aarch64_cortex-a53/packages/` indexes, served over HTTP),
   then:

   ```
   apk add strongswan-swanctl strongswan-mod-tpm strongswan-mod-openssl \
   	strongswan-mod-x509 strongswan-mod-pem strongswan-mod-pkcs1 \
   	strongswan-mod-pubkey strongswan-mod-constraints \
   	strongswan-mod-random strongswan-mod-kernel-netlink \
   	strongswan-mod-socket-default
   ```

   (The nonce plugin is in `strongswan` itself.)

2. Point the plugin at the TPM, in `/etc/strongswan.d/charon/tpm.conf`:

   ```
   tpm {
   	load = yes
   	tcti {
   		name = device
   		opts = /dev/tpmrm0
   	}
   }
   ```

3. Use the identity in a connection, such as `/etc/swanctl/conf.d/office.conf`
   (the packaged `swanctl.conf` includes `conf.d/`), then
   `/etc/init.d/swanctl restart`. This one is the ECC P-256 identity; for the
   RSA 2048 one, the certificate is `0x01c90000` and the key `0x81020000`.

   ```
   connections {
   	office {
   		remote_addrs = vpn.example.net
   		local {
   			auth = pubkey
   			cert-tpm {
   				handle = 0x01c90001
   			}
   		}
   		remote {
   			auth = pubkey
   			id = vpn.example.net
   		}
   		children {
   			office {
   				remote_ts = 10.0.0.0/8
   				start_action = start
   			}
   		}
   	}
   }
   secrets {
   	token-identity {
   		handle = 0x81020001
   	}
   }
   ```

- The AP's IKE identity is its certificate's subject, which carries the
  unit's MAC.
- The head end must trust that certificate. Without the certificate of
  Arista's issuing CA ("WiFi-TPM-Authority"), give the head end the AP's own
  certificate, read with `tpm2_nvread 0x01c90001 -o ap.der`; strongSwan
  trusts a peer certificate it was given (`remote.certs`), as in the test.
- Leave Arista's keys and NV indices in the TPM as they are. Nothing can make
  them again.

## In this directory

- `patches/openwrt/`: changes to OpenWrt's own files:
  - the device recipe;
  - calibration from ART;
  - sysupgrade;
  - LEDs;
  - the network roles;
  - the U-Boot environment's location;
  - the TPM module on this target.
- `files/`:
  - the device tree;
  - the board's scripts: the Wi-Fi firmware and board data copies (firmware
    hotplug), the port tool (`arista-c360-net`), the installer, the BLE
    start-up, and the LED and link watchers;
  - the airscan package;
  - the PoE power policy (`arista-c360-power`) and the radio plan
    (`arista-c360-radio`);
  - the TPM 2.0 software stack, `tpm2-tss` and `tpm2-tools`;
  - a fix to the Ethernet driver (`qca-nss-dp`): a received buffer is known
    by its address, not by a word written in it.
- `patches/feeds/packages/`: strongSwan's TPM plugin, with a fix that lets
  it sign with TPM keys that have no fixed signature scheme (as the factory
  identity keys).
- `feeds/`: a BlueZ 5.83 fix without which `btmgmt` can send no command.
- `tools/`: the USB stick maker, the console-driving installer, their tests,
  and a check of the RAM installer's contents.
