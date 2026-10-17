#!/bin/bash
# release.sh: gather the models' builds of one version into release assets.
#
#	./release.sh <version>     e.g. ./release.sh v2026.10.17
#
# Takes out/<model>/<version>/ of every model built at that version (by
# build.sh, from the tag) and puts in out/release/<version>/:
#   the images: initramfs-uImage.itb, squashfs-factory.ubi and
#     squashfs-sysupgrade.bin, as each model has them, and the manifests
#   the model's extras (the C-360's USB stick image)
#   <model>-feed-<version>.tar.gz: that build's package feed (feed/)
#   SHA256SUMS: one for all of them
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 1 ] || { sed -n '4p' "$0" | sed 's/^#\t*//' >&2; exit 2; }
V=$1
D=$HERE/out/release/$V

found=0
rm -rf "$D"
mkdir -p "$D"
for S in "$HERE"/out/*/"$V"; do
	[ -d "$S/feed" ] || continue
	m=$(basename "$(dirname "$S")")
	[ "$m" = release ] && continue
	for f in "$S"/openwrt-*-initramfs-uImage.itb "$S"/openwrt-*-squashfs-factory.ubi \
		"$S"/openwrt-*-squashfs-sysupgrade.bin "$S"/openwrt-*.manifest \
		"$S"/*-openwrt-installer.img.xz; do
		[ -e "$f" ] && cp "$f" "$D/"
	done
	tar -C "$S" -czf "$D/$m-feed-$V.tar.gz" feed
	echo ">> $m"
	found=$((found + 1))
done
[ $found -gt 0 ] || { echo "no build of $V in out/<model>/$V" >&2; exit 1; }
(cd "$D" && sha256sum -- * > SHA256SUMS)
echo ">> done: $D"
