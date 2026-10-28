# OpenWrt main

The C-360, C-260, C-230, W-318 and W-118 on OpenWrt main, as the lab units run them. Main
has the new Ethernet driver (qca_edma with multi-queue RX and TX: 9.3 Gb/s
up and 4.5 Gb/s down at 10G on the C-360, against 1.4 and 2.05 on 25.12),
and the devices' upstream pull requests are written for it.

```
main/build-main.sh ipq807x     # the C-360, the C-260 and the C-230
main/build-main.sh ipq60xx     # the W-318
main/build-main.sh ipq40xx     # the W-118 (target ipq40xx)
```

Out, in `out/main/<version>/`: `c360/`, `c260/`, `c230/`, `w318/`, `w118/`
with each model's images (including the C-360's USB stick image),
`feed-<subtarget>/` with the build's packages and every kernel module, and
`SHA256SUMS`. The models' `INSTALL.md` cover installing; main's images are
named `arista_c-360`, `arista_c-260`, `arista_c-230`, `arista_w-318` and
`arista_w-118`, and their board names are `arista,c-360`, `arista,c-260`,
`arista,c-230`, `arista,w-318` and `arista,w-118`.

**Every network port is in the LAN by default**, as upstream review settled
for all four models: on a fresh install the C-360's and C-260's Ethernet 1
and 2, the W-318's uplink and Network 1-3, the W-118's uplink and LAN 1-3
are all in `br-lan`, which runs no spanning tree. Two of them cabled to the
same switch make a loop: cable one, or turn on STP, or take the others out
of the bridge (the port tools do). Upgrades keep a unit's own settings.

## What it is built from

- `openwrt.lock`: OpenWrt main and its feeds, pinned; and the board files.
- `patches/openwrt/`, applied in order:
  - 0001-0012: the qualcommax devices, as their pull requests stand
    ([#25941](https://github.com/openwrt/openwrt/pull/25941) C-360,
    [#25937](https://github.com/openwrt/openwrt/pull/25937) C-260,
    [#25947](https://github.com/openwrt/openwrt/pull/25947) W-318). Where two
    add to the same list, the C-360's and C-260's entries are joined.
  - 0013: the ath11k monitor trim message at debug level
    ([#25988](https://github.com/openwrt/openwrt/pull/25988)).
  - 0014-0017: the W-118 ([#26028](https://github.com/openwrt/openwrt/pull/26028));
    0014 is also sent alone
    ([#26027](https://github.com/openwrt/openwrt/pull/26027): ipq40xx's
    inittab ran a login on ttyMSM1, the W-118's Bluetooth UART).
  - 0018, local: the 25.12 images' board names in `SUPPORTED_DEVICES`, so a
    unit on a 25.12 image can sysupgrade to main. Its port names change
    (eth0/eth1 become lan1/lan2): upgrade without settings (`sysupgrade -n`)
    or carry them over renamed.
  - 0019-0020: the C-230 (device, radio LEDs), its pull request not yet
    sent; made on top of 0001-0018, so it joins the C-260's and C-360's
    entries in the shared lists.
  - 0021: ath11k checks a monitor MSDU's buffer address against the
    buffer its cookie names (ath11k patch 102, meant for upstream). The
    device sometimes lists a buffer it handed back already, whose buf_id
    names a new buffer it still holds; ath11k freed that one, and the
    device wrote a frame into freed memory: the C-360's monitor-mode
    memory corruption (782 times in 32 minutes on the Living Room unit,
    2026-10-24; `c360/mon-corruption-2026-10-23/` in the Desktop
    workspace).
  - 0022, local: ath10k-ct anchors a QCA988x's rx levels to -95, as
    upstream ath10k does, not to the firmware's noise floor (unset for 2 s
    after each firmware start, -98 to -108 after), which made a scan
    radio's client levels read up to 20 dB under its beacon levels. Tested
    on a C-260 with the module built from it (`c260/RECORD.md` in the
    Desktop workspace).
  - 0023: ath11k no longer takes a monitor PPDU ID change to 0 (at a wrap)
    for no change (ath11k patch 103, meant for upstream). Before, the MPDU
    chain it had built was neither delivered nor freed: 37 lost in 47
    minutes with a monitor on each C-360 serving radio, none with the
    patch (Living Room unit, 2026-10-24).
  - 0024: the survey of the channel in use (ath11k patches 104 and 105,
    meant for upstream). 104: a channel switch (CSA, hostapd's switch_chan)
    left ar->rx_channel at the old channel, so the survey kept flagging that
    one as in use. 105: the in-use channel's noise floor came from the
    firmware's bss channel info event, which sits near -109 dBm on 5 GHz
    and -102 on 2.4 GHz on IPQ8074 (as on Arista's own firmware); it now
    comes from the firmware's pdev stats, the measured value (-94 and -96 on
    a C-260 at the same moment), and stays with the channel once the radio
    leaves it. Tested 2026-10-24 on a C-260 with the modules built from it,
    loaded from RAM: in-use survey -95/-96 against -106/-102 before, equal
    to the firmware's pdev stats; after a CSA from channel 60 to 36 only 36
    was in use (-92, as the firmware) and 60 kept its last measured -95.
    All three ath11k patches (104-106) were sent upstream 2026-10-24.
  - 0025: beacon stats with more than one started vdev (ath11k patch
    106, sent upstream). Reading `fw_stats/beacon_stats` timed out on
    every radio with more than one VAP: each per-vdev request reset the
    count that completion waited on. It now completes on each reply, as
    ath12k does. Tested 2026-10-24 on a C-260 (4 VAPs per radio), modules
    loaded from RAM: both radios list all four VAPs at once, against
    "Operation timed out" after 3 s before.
  - 0026: ucode's ubus module reconnects when ubusd drops it (patches 120
    and 121, for upstream ucode). Before, a ubusd restart left netifd's
    `network.wireless` and hostapd's and wpa_supplicant's objects gone
    until those processes restarted (libubus' default connection_lost does
    nothing once uloop has dropped the socket). Now the connection retries
    every second, and its objects and event listeners come back. Tested
    2026-10-24 on a C-260 with the module bind-mounted: after `killall
    ubusd`, `network.wireless`, `hostapd`, `wpa_supplicant` and the per-BSS
    objects were back within seconds, on the same PIDs. rpcd, dnsmasq,
    odhcpd, odhcp6c and usteerd (C daemons) still don't reconnect.
  - 0027: the C daemons the images ship reconnect when ubusd restarts too
    (package patches, one per project, meant for upstream). rpcd and odhcpd
    retry every second (odhcpd also renews its event and its netifd
    subscription). odhcp6c no longer frees its context on a failed
    reconnect, which left it polling a stale socket and freeing the context
    twice on exit. dnsmasq no longer frees its context inside libubus'
    callback, and wakes every quarter second until ubusd is back. ujail -u
    binds the `/var/run/ubus` directory read-only instead of the socket
    file, which kept a jailed dnsmasq or ntpd on the dead ubusd for good.
    usteer is not in the images and is not covered.
  - 0028: hostapd removes the interfaces of a phy that is gone. After an
    ath11k module reload, hostapd kept the old phy's interfaces and their
    `hostapd.<ifname>` objects beside the new ones: netifd's teardown for
    the old phy reached `iface_set_config()`, which opened the phy before
    acting on the empty config, found it gone, and returned. `wifi reconf`
    sends no teardown at all, so `config_set` now also drops the interfaces
    of any phy that no longer exists.
  - 0029: the dnsmasq user may publish `dnsmasq.dns`. dnsmasq first connects
    to ubus as root, before dropping privileges; on a reconnect it is the
    dnsmasq user, the ACL allowed only `dnsmasq`, ubusd refused
    `dnsmasq.dns`, and dnsmasq gave up on ubus for good.
  - Tested 2026-10-27 on a C-260 from RAM (the -44 binaries bind-mounted over
    the installed image): after `killall ubusd` all 37 ubus objects were back
    on the same PIDs (rpcd, odhcpd, odhcp6c, and dnsmasq once 0029's ACL was
    in place); the jail held the `/var/run/ubus` directory read-only and saw
    the new socket. After an ath11k reload, `wifi` and `wifi reconf` both left
    only the new phy's `hostapd.*` object, with hostapd not restarted.
  - 0030 (B87): the watchdog stays armed through a sysupgrade's reboot.
    `upgraded` (PID 1 during a sysupgrade) fed the watchdog while stage 2
    ran, and stage 2 does the final `reboot -f` itself, so a reboot that
    stalled in the kernel was never reset (a C-360 hung 3 hours until it was
    power-cycled). Stage 2 now sends SIGHUP to PID 1 before `reboot -f`, and
    `upgraded` stops feeding the watchdog but leaves it armed. procd ignores
    SIGHUP. Package patch 101 for upstream procd; procd PKG_RELEASE 4.
  - 0031 (B93): wifi-scripts writes an 802.1X BSS's RADIUS accounting server
    once. `iface_accounting_server()` ran in `iface_auth_type()`'s eap branch
    and again in `generate()`, so hostapd had two accounting servers and sent
    each `radius_acct_req_attr` (a NAS-Identifier) twice per
    Accounting-Request. Tested 2026-10-28 on the C-260 (`ap.uc` bind-mounted):
    one `acct_server_addr` and one `radius_acct_req_attr` per radio, all 8
    VAPs up. wifi-scripts PKG_RELEASE 5.
  - 0032: an automatic 5 GHz channel starts outside DFS. hostapd's ACS
    could pick a DFS channel at every start (a reboot, a config change, a
    `wifi` reload), and the radio then sent nothing for its 60 s radar
    check: the C-260 came up on 60, then on 100, 2026-10-28. A wifi-device
    option, `dfs_look_first` (on by default), sets `acs_exclude_dfs` where
    the channel is automatic and a block outside DFS fits the width and
    channel list (not at 160 MHz); `dfs-look` (below) may move the radio to
    a DFS channel once it has looked. `dfs_look_first '0'` is the old
    behaviour, and `acs_exclude_dfs '1'` still keeps a radio off DFS
    altogether. wifi-scripts PKG_RELEASE 6.
  - 0033 (B94): mac80211 flushes TX for a new key only where it needs
    tailroom (mac80211 patch 423, for upstream). Every pairwise key a
    station got waited in `ieee80211_key_link()` for `synchronize_net()`, an
    RCU grace period, when the AP's tailroom count went from 0 to 1: on a
    BSS without PMF all of ath11k's keys are in the hardware and the count
    is 0 between stations (with PMF its software BIP keys hold it at 1).
    hostapd waited on it before letting the station on: 31-65 ms per 4-way
    handshake on the C-260 (HZ=100). A new key isn't used before it is
    published, after the hardware upload, so TX is now flushed then, and
    only where the key still needs tailroom. Tested 2026-10-28 on the C-260
    (the module loaded from RAM, Aeolus's roam tests, WPA2-PSK without
    PMF): NEW_KEY to authorized 0-2 ms in 13 of 13 handshakes. mac80211
    PKG_RELEASE 14.
  - 0034 (B88): upstream f394cbd0980c, mac80211 doesn't estimate airtime
    for rate widths it can't price (mac80211 patch 424, a backport). After
    an OFDMA transmission ath11k reports a station's TX rate as an HE RU,
    and the next station dump hit a `WARN_ON_ONCE` at `airtime.c:532`
    (once per boot on two C-360s). mac80211 PKG_RELEASE 15. Not tested
    live: the warning needs an OFDMA station and comes once a boot.
  - 0035 (B90): ath11k doesn't report a QCN9074's chan-info noise floor
    (ath11k patch 107, for upstream). On the QCN9074 family (the C-360's
    6 GHz card and its QCN9072 scan radio) every off-channel survey entry
    read about -107 dBm, busy or quiet, below thermal noise, where the
    IPQ8074 read -93 to -98 on the same channels and followed them. Those
    entries now carry time and busy but no noise; other chips and in-use
    channels are unchanged. Tested 2026-10-28 on a C-360 with the three
    ath11k modules loaded from RAM (it adds to struct ath11k_hw_params,
    which struct ath11k_base embeds, so ath11k_ahb and ath11k_pci must come
    from the same build: with only ath11k.ko swapped, the C-360 rebooted).
    mac80211 PKG_RELEASE 16.
  - 0036 (B6): a disabled radio doesn't set the regulatory domain. The
    domain is the system's, but every radio's setup ran `iw reg set` with
    its own country, disabled radios too, and hostapd.uc gave every hostapd
    the last radio's country. The default config gives a 6 GHz radio '00',
    so a C-360 with its 6 GHz radio disabled went to the world domain at
    boot; its IPQ8074 firmware refused it and the 5 GHz radar check failed
    (3 boots in 4). Disabled radios are skipped, and the domain isn't set
    again to what it already is. Tested 2026-10-28 on the C-260 from RAM
    (no regression: no redundant `iw reg set`, US kept, 8 VAPs).
    wifi-scripts PKG_RELEASE 7.
  - Regenerated 2026-10-19 by replaying the pull requests' heads onto the
    pinned main (C-360 685d83f8, C-260 fe81f185, W-318 91b2c345, trim
    3a0b0a79, W-118 d41cbf7d).
- `patches/feeds/packages/`:
  - 0001 is gone. It made bluez-daemon depend on kmod-crypto-user, because
    25.12's bluetoothd needed AF_ALG to give an LE-only controller its
    static address. Main's BlueZ (5.86) does not: on a C-360 with the AF_ALG
    modules absent, bluetoothd set the static address and registered hci0
    (2026-10-18).
  - 0002: strongSwan's TPM 2.0 plugin (`strongswan-mod-tpm`), with the source
    patch for keys without a fixed signature scheme, as Arista's factory
    identity keys are: the 25.12 patch (`../c360/patches/feeds/packages/`)
    on main's strongswan 6.0.7-r9. On main the identity authenticated IKEv2
    on a C-360 and a W-318, RSA (RSA-PSS) and ECC (ECDSA), with ESP across
    (`../c360/README.md`, "IPsec with the TPM identity"). Built for the feed
    (`=m`), not in the images. Not yet sent upstream.
- The board files (`ipq-wifi`): qca-wireless at OpenWrt's commit with the
  four board-file pull requests on it (#175 C-260, #176 C-360, #178 W-318,
  #179 W-118),
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
- `files/package/network/services/dfs-look`, in every model's images:
  after a 5 GHz radio has started outside DFS (0032), it looks at every 5
  GHz channel, with airscan's scan radio where the board has one (two
  scans and 5 GHz sweeps, about 2.5 minutes) or else by the radio's own
  scans (each channel twice, about a minute), and moves the radio to a DFS
  block by hostapd's `CHAN_SWITCH` only where that block rates better by 20
  points than its own and than the best outside DFS (Aeolus's rating: busy,
  noise, other networks heard). Once per start; a DFS block the radio
  left, or failed to get to, is left alone for a day. `dfs-look -n` only
  says what it would do. Tested 2026-10-28 on a C-260 from RAM: with the
  scan radio it stayed on 36-40 (10 against DFS 100-104's 2); with
  `-m 0` it moved to 124, and by its own scans (airscan stopped) it moved
  to 100 at the default margin (36-40 rated 23, 100-104 0), each up 62 s
  after the switch, all 8 VAPs back. 0.1-2 times its looks on the
  monotonic clock: on a C-360 just booted, NTP stepped the wall clock 12
  minutes mid-look and the look was given up (2026-10-28).
- `config/<subtarget>.seed`. Each model's own packages are `=m` and listed
  for its device, so they are in its images only; `=y` would put them in
  every image of the multi-profile build.

Nothing for a manager is in the images; kernel modules a manager needs come
from the build's module feed.

When the pull requests are merged, their patches go, `openwrt.lock` moves to
a main that has them, and only the models' own packages and scripts remain.
