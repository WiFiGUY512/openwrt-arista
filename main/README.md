# OpenWrt main: local patches

Patches the main-based images of these ports carry on top of OpenWrt main
and the upstream device PRs. They are not for upstream.

- `patches/mac80211/ath11k/960-wifi-ath11k-calibration-file-before-nvmem.patch`
  (into `package/kernel/mac80211/patches/ath11k/`): a calibration file in
  place comes before the device tree's nvmem cell. The C-360's dual 5 GHz
  plan (`arista-c360-radio`) writes the IPQ8074's calibration from ART
  0x71800 as `cal-ahb-c000000.wifi.bin`; the device tree names 0x1000, the
  6 GHz plan's. With no such file nothing changes.
