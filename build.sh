#!/bin/bash
# build.sh: build OpenWrt for an Arista access point from source.
#
#	./build.sh <model> [OpenWrt directory]     e.g. ./build.sh c360
#
# The model's directory holds what its build needs:
#   openwrt.lock      the OpenWrt and feed commits it is built against
#   patches/openwrt/  patches to OpenWrt's own files
#   patches/feeds/<feed>/  patches to a feed's packages
#   files/            the model's own files, at their places in the tree
#   feeds/            files added to the feeds (patches to feed packages)
#   config/<device>.seed  the build configuration, before make defconfig
#   model.sh          its device name and target, and its checks
#
# Each patch is applied to the committed state of the files it touches, so a
# tree from an earlier build takes the current version of every patch.
#
# Every kernel module is built (CONFIG_ALL_KMODS, as OpenWrt's own build
# servers do), so the kernel's version does not depend on which modules an
# image carries, and the modules form a package feed for exactly this kernel.
# OpenWrt's own module feeds do not fit it; this feed does.
#
# Out, in out/<model>/<this repo's version>/: the images; feed/, signed with
# this build's key, with the target's packages and every kernel module in
# feed/packages/ and every other package the build made in
# feed/<arch>/<feed>/; the model's extras (such as a USB stick image); and
# SHA256SUMS.
#
# Needs a Linux host with OpenWrt's build prerequisites
# (https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem).
# A first build takes hours; later ones reuse the tree (default
# build/<model>/openwrt).
#
# The build signs its packages with private-key.pem in the OpenWrt directory,
# made on the first build, and the image trusts its public half. Keep that key
# private, and reuse it for every build whose feed you publish.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { sed -n '4p' "$0" | sed 's/^#\t*//' >&2; exit 2; }
MODEL=$1
MODEL_DIR=$HERE/$MODEL
[ -f "$MODEL_DIR/model.sh" ] || { echo "no model $MODEL (no $MODEL/model.sh)" >&2; exit 2; }
W=$(realpath -m "${2:-$HERE/build/$MODEL/openwrt}")
VERSION=$(git -C "$HERE" describe --tags --always --dirty 2>/dev/null || echo unversioned)
OUT=$HERE/out/$MODEL/$VERSION
. "$MODEL_DIR/openwrt.lock"
. "$MODEL_DIR/model.sh"

say() { echo ">> $*"; }

# unpatch DIR PATCH...: the files the patches touch, back to their committed
# state in the git checkout DIR (undoing these patches from an earlier build)
unpatch() {
	local dir=$1 p f
	shift
	for p in "$@"; do
		[ -e "$p" ] || continue
		for f in $(git -C "$dir" apply --numstat "$p" | cut -f3); do
			if git -C "$dir" cat-file -e "HEAD:$f" 2>/dev/null; then
				git -C "$dir" checkout -q HEAD -- "$f"
			else
				rm -f "$dir/$f"
			fi
		done
	done
}

# apply_patches DIR PATCH...: the patches, onto the committed state of the
# files they touch in the git checkout DIR
apply_patches() {
	local dir=$1 p
	shift
	unpatch "$dir" "$@"
	for p in "$@"; do
		[ -e "$p" ] || continue
		git -C "$dir" apply --whitespace=nowarn "$p" || { echo "$(basename "$p") does not apply to $dir" >&2; exit 1; }
		say "applied $(basename "$p")"
	done
}

# model_files SRC DIR LIST: the files under SRC, copied into DIR with their
# modes and times. A file an earlier build copied (listed in LIST) that SRC no
# longer has goes back to its committed state in DIR, or away, so a tree from
# an earlier build carries nothing the model has dropped.
model_files() {
	local src=$1 dir=$2 list=$3 f
	[ -d "$src" ] || return 0
	(cd "$src" && find . ! -type d | sed 's|^\./||' | LC_ALL=C sort) >"$list.new"
	if [ -f "$list" ]; then
		LC_ALL=C comm -23 "$list" "$list.new" | while IFS= read -r f; do
			if git -C "$dir" cat-file -e "HEAD:$f" 2>/dev/null; then
				git -C "$dir" checkout -q HEAD -- "$f"
			else
				rm -f "$dir/$f"
			fi
			say "removed $f (no longer in the model)"
		done
	fi
	cp -rp "$src/." "$dir/"
	mv "$list.new" "$list"
}

# modules_fit OUT PACKAGE...: each module in the feed is built for the image's kernel
modules_fit() {
	local out=$1 k f dep
	shift
	k=$(grep -E '^kernel ' "$out"/*$DEVICE*.manifest | cut -d' ' -f3)
	for p in "$@"; do
		f=$(find "$out/feed" -name "$p-[0-9]*.apk" | head -1)
		[ -n "$f" ] || { echo "$p is missing from the module feed" >&2; exit 1; }
		dep=$(staging_dir/host/bin/apk adbdump "$f" 2>/dev/null | grep -oE 'kernel=[^ ]+' | head -1)
		[ "$dep" = "kernel=$k" ] || { echo "$p needs $dep, but the image's kernel is $k" >&2; exit 1; }
	done
}

# 1. OpenWrt at the pinned commit
if [ ! -d "$W/.git" ]; then
	say "cloning OpenWrt into $W"
	mkdir -p "$(dirname "$W")"
	git clone "$OPENWRT_URL" "$W"
fi
cd "$W"
if [ "$(git rev-parse HEAD)" != "$OPENWRT_COMMIT" ]; then
	unpatch . "$MODEL_DIR"/patches/openwrt/*.patch
	git diff --quiet || { echo "$W has changes of its own and is not at $OPENWRT_COMMIT; build in a fresh directory" >&2; exit 1; }
	git fetch -q origin
	git checkout -q "$OPENWRT_COMMIT"
fi
say "$MODEL_NAME on OpenWrt $(git log -1 --format='%h %cd %s' --date=short)"

# 2. patches to OpenWrt's own files
apply_patches . "$MODEL_DIR"/patches/openwrt/*.patch

# 3. the model's own files, with their modes, and their times: OpenWrt's
# kernel stamp hashes the times of target/linux files, so a fresh time on an
# unchanged file would rebuild the kernel and every module
model_files "$MODEL_DIR/files" . .model-files
fix_modes

# 4. the feeds, at their pinned commits, and the model's additions to them
: >feeds.conf
for f in packages luci routing telephony video; do
	v=FEED_$f
	[ -n "${!v:-}" ] && echo "src-git $f ${!v}" >>feeds.conf
done
./scripts/feeds update -a >/dev/null
for d in "$MODEL_DIR"/patches/feeds/*/; do
	[ -d "$d" ] && apply_patches "feeds/$(basename "$d")" "$d"*.patch
done
./scripts/feeds update -i >/dev/null
./scripts/feeds install $FEEDS_INSTALL >/dev/null
model_files "$MODEL_DIR/feeds" feeds .model-feeds
say "feeds: $(sed 's/^src-git \([a-z]*\) .*\^\(.\{8\}\).*/\1 \2/' feeds.conf | tr '\n' ' ')"

# 5. configure and build
cp "$MODEL_DIR/config/$DEVICE.seed" .config
make defconfig >/dev/null
grep -q "^CONFIG_TARGET_${TARGET%%/*}_${TARGET#*/}_DEVICE_$DEVICE=y" .config || { echo "$DEVICE is not selected after defconfig" >&2; exit 1; }
O=bin/targets/$TARGET
# the feed must hold only what this build made, and its modules only ones
# built for this kernel (make packs again any package it finds missing)
rm -rf $O/packages $O/kmods $O/*$DEVICE* bin/packages
say "building (log: $W/build.log)"
# a module that fails to build does not stop the image, as on OpenWrt's servers
make -j"$(nproc)" IGNORE_ERRORS=m >build.log 2>&1 || { tail -40 build.log; echo "the build failed; see $W/build.log" >&2; exit 1; }

# 6. collect: the images, the target's feed with every module, and the
# other packages' feeds
rm -rf "$OUT"
mkdir -p "$OUT"
cp $O/*$DEVICE* "$OUT/"
for idx in $(find $O bin/packages -name packages.adb); do
	d=$(dirname "$idx")
	case $d in
	$O/*) rel=${d#$O/} ;;
	*) rel=${d#bin/packages/} ;;
	esac
	mkdir -p "$OUT/feed/$rel"
	cp "$d"/*.apk "$d/packages.adb" "$OUT/feed/$rel/"
done
failed=$(grep -cE 'ERROR: package/.* failed to build' build.log || true)

# 7. the model's checks and extras
after_build "$OUT"
(cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum >SHA256SUMS)

say "done: $OUT"
say "kernel $(grep -E '^kernel ' "$OUT"/*$DEVICE*.manifest | cut -d' ' -f3); $(find "$OUT/feed" -name 'kmod-*.apk' | wc -l) kernel modules in feed/; $failed modules failed to build (see build.log)"
