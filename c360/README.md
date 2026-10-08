# Arista C-360

A Wi-Fi 6E campus access point: a Qualcomm IPQ8074A with its own 2.4 and
5 GHz radios, two QCN9074 cards (one a 6 GHz serving radio, the other a
2.4/5/6 GHz scan radio), two 10 GbE ports with PoE in, a Nordic nRF52833
Bluetooth LE controller, an Infineon TPM 2.0 and a USB 3.0 port. Details in
[HARDWARE.md](HARDWARE.md); installing in [INSTALL.md](INSTALL.md).

## What works

Seen working on a unit unless marked *(built, not yet on a unit)*.

- **All four radios.** radio0 (5 GHz) and radio1 (2.4 GHz) are on the
  IPQ8074, and radio3 (6 GHz) is on the first QCN9074. radio2, the second
  QCN9074, is the scan radio and serves no clients (below).
- **Ethernet: two 10 GbE ports, both PoE in** (Aquantia AQR113C: 10G, 5G,
  2.5G, 1G, 100M). eth0 is Ethernet 1 and eth1 is Ethernet 2.
  - Both ports link at 10 Gb/s and at 2.5 Gb/s, and pass traffic both ways.
  - MACs and radio calibration are read from the unit's own ART partition.
  - Not yet measured: throughput at 10G.
- **Both ports are LAN; there is no WAN.** On a fresh install they are one
  LACP bond (802.3ad, `bond0`), and `br-lan` on it takes its address by DHCP.
  - With an LACP switch the two links aggregate. With one cable, or a switch
    without LACP, the bond runs on a single link, so two cables never make a
    loop.
  - LACP was seen working against an Arista switch (both links collecting
    and distributing), on a config set by hand. The fresh-install default
    *(built, not yet on a unit)* was tested on scratch configs.
- **VXLAN:** netifd's `vxlan` protocol and `kmod-vxlan` are in the image
  *(built, not yet on a unit)*. The kernel's VXLAN, from this build's
  module, was tested on a unit: VNI 42 between two network namespaces, with
  a ping across the overlay.
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
  - a spectrum survey (ath11k spectral scan; per 20 MHz, the share of samples
    above -82 dBm);
  - a survey of every network on every 2.4, 5 and 6 GHz channel;
  - a survey of the clients on the channels that have networks;
  - a Bluetooth LE survey, on the nRF52833.

  It detects:
  - wired rogues: a network relaying the AP's own wired ARP probes that isn't
    one of its own;
  - evil twins: one of its SSIDs on a network that never relays them;
  - its own BSSID heard where it isn't;
  - deauthentication floods.

  The wired probes go out on each of the AP's L2 domains (bridges, VLANs, a
  bond, never the bond's member ports), read again every round, so the probes
  follow network changes.
  - Results: `ubus call airscan status|spectrum|bss|clients|ble`, and JSON in
    `/tmp/airscan`.
  - Settings: `/etc/config/airscan`. List your own SSIDs in `trusted_ssid`,
    or your other APs show up as wired rogues.
- **TPM 2.0:** an Infineon SLB 9670 (firmware 7.85) on SPI (`tpm_tis_spi`).
  `/dev/tpm0` and the resource manager `/dev/tpmrm0` work, and the TPM is the
  kernel's hardware random source (`tpm-rng`).
  - `tpm2-tools` 5.8, on `tpm2-tss` 4.2, is in the image (OpenWrt 25.12
    packages neither): random numbers, keys, signing and verifying, sealing.
    Tested on a unit as packages from the same recipes; the image that
    carries them is *(built, not yet on a unit)*.
  - Each unit's factory identity, Arista's certificates in the TPM with their
    keys, reads out with `tpm2_nvread` (HARDWARE.md).
- **IPsec with the unit's TPM identity:** strongSwan with its TPM plugin
  (`strongswan-mod-tpm`, in the build's feed) authenticates IKEv2 with a
  factory certificate and its key, which never leaves the TPM. Tested on a
  unit: an IKEv2 exchange and an ESP tunnel, with the RSA identity and with
  the ECC one. Setup below.
- **USB storage** on the Type-A port.
- **sysupgrade**, and **Arista's system kept as a fallback:** OpenWrt lives in
  NAND slot 0, and Arista's slot 1 is never written.

## What doesn't (yet)

- **Measured boot.** Arista's U-Boot doesn't extend the TPM's PCRs (all read
  zero after boot), so the TPM can't attest to what booted.
- **Zigbee and Thread.** The nRF52833's radio can do 802.15.4, but Arista's
  firmware is Bluetooth LE only, and signed.
- **The USB stick installer has not been run on a unit yet** (INSTALL.md,
  section A). The manual install (section B) has.

## Requirements

- **Arista's system in slot 1.** OpenWrt contains no Arista files. At first
  boot it copies the QCN9074 firmware and board files, unmodified, from the
  unit's own Arista system in NAND slot 1.
  - Only Arista's build of that firmware (`WLAN.HK.2.5.r4`) runs these cards;
    every public `ath11k-firmware` build tested stops during start-up.
  - The installer checks slot 1 before writing anything.
- **Two ath11k fixes**, in `files/package/kernel/mac80211/patches/ath11k/`:
  with the board's fixed host-memory region, the QCN9074 must be given its
  calibration area and paged memory inside that region, or its firmware falls
  silent.

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
   	strongswan-mod-pubkey strongswan-mod-constraints strongswan-mod-nonce \
   	strongswan-mod-random strongswan-mod-kernel-netlink \
   	strongswan-mod-socket-default
   ```

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
  - the board's scripts: the first-boot Wi-Fi firmware copy, the LACP bond
    on a fresh config, the installer, the BLE start-up, and the LED and link
    watchers;
  - the airscan package;
  - the TPM 2.0 software stack, `tpm2-tss` and `tpm2-tools`;
  - the two ath11k fixes.
- `patches/feeds/packages/`: strongSwan's TPM plugin, with a fix that lets
  it sign with TPM keys that have no fixed signature scheme (as the factory
  identity keys).
- `feeds/`: a BlueZ 5.83 fix without which `btmgmt` can send no command.
- `tools/`: the USB stick maker, the console-driving installer, their tests,
  and a check of the RAM installer's contents.
