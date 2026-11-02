# OpenWrt for Arista access points

Everything needed to run [OpenWrt](https://openwrt.org) on Arista Wi-Fi
access points: the device support, the patches it needs, the installer, and a
build script that makes the images from OpenWrt's source.

This is an independent project. It is not made, endorsed or supported by
Arista Networks, and it contains no Arista software: each unit's own copy of
the files OpenWrt needs from Arista's system is copied from that unit at
first boot.

| Model | SoC | OpenWrt | Status |
|---|---|---|---|
| [C-360](c360/README.md) | Qualcomm IPQ8076A + QCN9074 + QCN9072 | 25.12, main | Working: all radios, Bluetooth LE, the scan radio, both 10 GbE ports |
| [C-260](c260/README.md) | Qualcomm IPQ8078A + QCA9882 | 25.12, main | Working: all radios, the scan radio, Bluetooth, both Ethernet ports (5 Gb/s, PoE in on either), LEDs, button, USB, PoE power policy, install and sysupgrade |
| [C-230](c230/README.md) | Qualcomm IPQ8071A + QCA9882 | main | Working on one unit: all radios (access points on the IPQ8071A's), the scan radio, Bluetooth (with Arista's PS keys file), both Ethernet ports (5 Gb/s with PoE in, 1 Gb/s), LEDs, button, USB, TPM, PoE power policy, install and sysupgrade |
| [C-200](c200/README.md) | Qualcomm IPQ6010 | main | Working on one unit: both radios, Ethernet (943 Mbit/s out with 0075), LEDs, button, TPM, install and sysupgrade |
| [W-318](w318/README.md) | Qualcomm IPQ6010 + QCN9072 | 25.12, main | Working: all radios, Bluetooth LE, the TPM, Ethernet, LEDs, button, USB, PoE power policy, install and sysupgrade |
| [W-118](w118/README.md) | Qualcomm IPQ4019 + QCA9882 | main | Working: all radios, Bluetooth LE, Ethernet, LEDs, button, PoE out, install and sysupgrade; the scan radio's airscan not yet run |

## Download

Built images are on the [releases page](https://github.com/WiFiGUY512/openwrt-arista/releases),
one release for all models, each built from the release's tag with
`build.sh` and gathered with `release.sh`:

- `openwrt-…-initramfs-uImage.itb`: the RAM system each install starts from
- `openwrt-…-squashfs-factory.ubi` (C-360, C-260): what the install writes
- `openwrt-…-squashfs-sysupgrade.bin`: for `sysupgrade`, and the W-318's install
- `c360-openwrt-installer.img.xz`: the C-360's USB stick
- `<model>-feed-<version>.tar.gz`: that build's package feed, with every
  kernel module (see below)
- `SHA256SUMS`: check what you downloaded with `sha256sum -c SHA256SUMS --ignore-missing`

To install a kernel module, unpack the feed of the build your AP runs, copy
the module's `.apk` (from `feed/packages/`) and any it depends on to the AP,
and `apk add` them; the images trust the key the feed is signed with. Or
serve the unpacked `feed/` over HTTP and add its `packages.adb` files to
`/etc/apk/repositories.d/customfeeds.list`.

## Build

On Linux, with [OpenWrt's build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem):

```
./build.sh c360
```

It clones OpenWrt at the commit the model is pinned to, applies the model's
patches and files, and builds. The images, a package feed with every kernel
module and every package the build made, and for the C-360 a USB stick image
for its installer end up in `out/<model>/<version>/`. A first build takes
hours.

**Kernel modules come from this build's feed, not OpenWrt's.** A kernel
module installs only on the exact kernel it was built for, and these images'
kernels are built here, so OpenWrt's own module feeds do not fit them. Every
module is built with the image (as OpenWrt's build servers do), so any of them
can be installed later. Ordinary packages install from OpenWrt's feeds as on
any OpenWrt device.

### OpenWrt main

```
main/build-main.sh ipq807x     # the C-360 and the C-260
main/build-main.sh ipq60xx     # the W-318
main/build-main.sh ipq40xx     # the W-118
```

The same models on OpenWrt main, built from the devices' upstream pull
requests as they stand: main's Ethernet driver moves several times the
traffic of 25.12's (on the C-360 at 10G, 9.3 Gb/s up and 4.5 down against
1.4 and 2.05). Main's board names are `arista,c-360`, `arista,c-260`,
`arista,w-318` and `arista,w-118`. The W-118 is built on main only. See
[main/README.md](main/README.md).

## Install

Each model's `INSTALL.md`: [c360/INSTALL.md](c360/INSTALL.md), [c260/INSTALL.md](c260/INSTALL.md), [w318/INSTALL.md](w318/INSTALL.md), [w118/INSTALL.md](w118/INSTALL.md), [c200/INSTALL.md](c200/INSTALL.md).

## Layout

```
build.sh            builds one model: ./build.sh <model>
release.sh          gathers the models' builds of a version: ./release.sh <version>
main/               the models on OpenWrt main: main/build-main.sh <subtarget>
<model>/
  README.md         what works, what doesn't
  INSTALL.md        installing and going back
  HARDWARE.md       what the hardware is and how it was worked out
  model.sh          the device's name, target and checks, for build.sh
  openwrt.lock      the OpenWrt and feed commits it builds against
  config/           the build configuration
  patches/openwrt/  patches to OpenWrt's own files
  patches/feeds/    patches to OpenWrt's feeds, one directory per feed
  files/            the model's own files, at their places in the OpenWrt tree
  feeds/            files added to packages in OpenWrt's feeds
  tools/            installer tools
```

## License

GPL-2.0, as OpenWrt (see [LICENSE](LICENSE)); files that say otherwise carry
their own SPDX tag.
