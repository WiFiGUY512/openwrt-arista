# OpenWrt main

The C-360, C-260 and W-318 on OpenWrt main, as the lab units run them. Main
has the new Ethernet driver (qca_edma with multi-queue RX and TX: 9.3 Gb/s
up and 4.5 Gb/s down at 10G on the C-360, against 1.4 and 2.05 on 25.12),
and the devices' upstream pull requests are written for it.

```
main/build-main.sh ipq807x     # the C-360 and the C-260
main/build-main.sh ipq60xx     # the W-318
```

Out, in `out/main/<version>/`: `c360/`, `c260/`, `w318/` with each model's
images (including the C-360's USB stick image), `feed-<subtarget>/` with the
build's packages and every kernel module, and `SHA256SUMS`. The models'
`INSTALL.md` cover installing; main's images are named `arista_c-360`,
`arista_c-260` and `arista_w-318`, and their board names are `arista,c-360`,
`arista,c-260` and `arista,w-318`.

## What it is built from

- `openwrt.lock`: OpenWrt main and its feeds, pinned; and the board files.
- `patches/openwrt/`, applied in order:
  - 0001-0012: the devices, as their pull requests stand
    ([#25941](https://github.com/openwrt/openwrt/pull/25941) C-360,
    [#25937](https://github.com/openwrt/openwrt/pull/25937) C-260,
    [#25947](https://github.com/openwrt/openwrt/pull/25947) W-318). Where two
    add to the same list, the C-360's and C-260's entries are joined.
  - 0013: the ath11k monitor trim message at debug level
    ([#25988](https://github.com/openwrt/openwrt/pull/25988)).
  - 0014, local: the 25.12 images' board names in `SUPPORTED_DEVICES`, so a
    unit on a 25.12 image can sysupgrade to main. Its port names change
    (eth0/eth1 become lan1/lan2): upgrade without settings (`sysupgrade -n`)
    or carry them over renamed.
- `patches/feeds/packages/`:
  - 0001: bluez-daemon depends on kmod-crypto-user (bluetoothd needs AF_ALG
    to give an LE-only controller, such as the C-360's and W-318's, its
    static address). Local, not yet sent upstream.
  - 0002: strongSwan's TPM 2.0 plugin (`strongswan-mod-tpm`), with the source
    patch for keys without a fixed signature scheme, as Arista's factory
    identity keys are: the 25.12 patch (`../c360/patches/feeds/packages/`)
    on main's strongswan 6.0.7-r9. On main the identity authenticated IKEv2
    on a C-360 and a W-318, RSA (RSA-PSS) and ECC (ECDSA), with ESP across
    (`../c360/README.md`, "IPsec with the TPM identity"). Built for the feed
    (`=m`), not in the images. Not yet sent upstream.
- The board files (`ipq-wifi`): qca-wireless at OpenWrt's commit with the
  three board-file pull requests on it (#175 C-260, #176 C-360, #178 W-318),
  combined by the build with a fixed committer and date, so it is the same
  commit (`QCA_COMMIT`) for everyone.
- `<model>/files/`: the models' packages and scripts: airscan and its LuCI
  app, the power policies, the C-360's radio plan, board data by country,
  Bluetooth, tpm2-tss/tpm2-tools, the installers and the Ethernet 2 tools.
  Left out, as main or the pull requests have their own: the 25.12 device
  trees, radio LED and vendor firmware scripts, qca-nss-dp's patch (main has
  qca_edma), the C-360's Ethernet LED defaults (in main's `01_leds`) and its
  link watch (written for 25.12's eth0; main's ports are lan1 and lan2).
- `files/`: main's own versions: the BLE power scripts (main's
  `bluetooth-uart` attaches the controllers), and the local ath11k patch 960
  (`package/kernel/mac80211/patches/ath11k/`): a calibration file in place
  comes before the device tree's nvmem cell. The C-360's dual 5 GHz plan
  (`arista-c360-radio`) writes the IPQ8074's calibration from ART 0x71800 as
  `cal-ahb-c000000.wifi.bin`; the device tree names 0x1000, the 6 GHz plan's.
  With no such file nothing changes. Not for upstream.
- `config/<subtarget>.seed`. Each model's own packages are `=m` and listed
  for its device, so they are in its images only; `=y` would put them in
  every image of the multi-profile build.

Nothing for a manager is in the images; kernel modules a manager needs come
from the build's module feed.

When the pull requests are merged, their patches go, `openwrt.lock` moves to
a main that has them, and only the models' own packages and scripts remain.
