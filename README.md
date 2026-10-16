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
| [C-360](c360/README.md) | Qualcomm IPQ8074A + 2 × QCN9074 | 25.12 | Working: all radios, BLE, the scan radio, both 10 GbE ports |
| [C-260](c260/README.md) | Qualcomm IPQ8078A + QCA988x | 25.12 | Working: all radios, Bluetooth, both 5 GbE ports, install and sysupgrade; LEDs next |

## Build

On Linux, with [OpenWrt's build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem):

```
./build.sh c360
```

It clones OpenWrt at the commit the model is pinned to, applies the model's
patches and files, and builds. The images, a USB stick image for the
installer, and a package feed with every kernel module and every package the
build made end up in `out/<model>/<version>/`. A first build takes hours.

**Kernel modules come from this build's feed, not OpenWrt's.** A kernel
module installs only on the exact kernel it was built for, and these images'
kernels are built here, so OpenWrt's own module feeds do not fit them. Every
module is built with the image (as OpenWrt's build servers do), so any of them
can be installed later. Ordinary packages install from OpenWrt's feeds as on
any OpenWrt device.

## Install

Each model's `INSTALL.md`: [c360/INSTALL.md](c360/INSTALL.md), [c260/INSTALL.md](c260/INSTALL.md).

## Layout

```
build.sh            builds one model: ./build.sh <model>
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
