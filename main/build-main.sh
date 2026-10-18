#!/bin/bash
# build-main.sh: build the Arista images on OpenWrt main from source.
#
#	main/build-main.sh <ipq807x|ipq60xx> [OpenWrt directory]
#
# ipq807x builds the C-360 and the C-260 (one multi-profile build: one
# kernel, one module feed), ipq60xx the W-318. What it builds from, all in
# this repository:
#   main/openwrt.lock        OpenWrt main, the feeds, and the board files'
#                            qca-wireless commits
#   main/patches/openwrt/    the devices as their upstream pull requests
#                            stand, and the port's local patches (0014-)
#   main/patches/feeds/      the port's patches to the feeds' packages
#   <model>/files/           each model's packages and scripts (airscan,
#                            power policies, radio plan, board data, the
#                            installers, the Ethernet 2 tools), less what
#                            OpenWrt main or the pull requests have instead
#   main/files/              main's own versions of a few of those
#   main/config/<sub>.seed   the build configuration, before make defconfig
#
# Every kernel module is built (CONFIG_ALL_KMODS), so the modules form a
# package feed for exactly this kernel. Out, in out/main/<this repo's
# version>/: <model>/ with its images, feed-<subtarget>/ with the build's
# packages, and SHA256SUMS. The tree defaults to build/main/openwrt; both
# subtargets can share it, one after the other.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
MAIN=$HERE/main
[ $# -ge 1 ] || { sed -n '4p' "$0" | sed 's/^#\t*//' >&2; exit 2; }
SUB=$1
case $SUB in
ipq807x) MODELS="c360 c260" DEVICES="arista_c-360 arista_c-260" ;;
ipq60xx) MODELS="w318" DEVICES="arista_w-318" ;;
*) echo "no subtarget $SUB (ipq807x or ipq60xx)" >&2; exit 2 ;;
esac
W=$(realpath -m "${2:-$HERE/build/main/openwrt}")
VERSION=$(git -C "$HERE" describe --tags --always --dirty 2>/dev/null || echo unversioned)
OUT=$HERE/out/main/$VERSION
. "$MAIN/openwrt.lock"

say() { echo ">> $*"; }

# restore DIR FILE: DIR/FILE back to its committed state in the git checkout
# that holds it, or away if that has no such file
restore() {
	local d b
	d=$(dirname "$1/$2") b=$(basename "$2")
	if [ -d "$d" ] && git -C "$d" cat-file -e "HEAD:./$b" 2>/dev/null; then
		git -C "$d" checkout -q HEAD -- "$b"
	else
		rm -f "$1/$2"
	fi
}

# unpatch DIR PATCH...: the files the patches touch, back to their committed state
unpatch() {
	local dir=$1 p f
	shift
	for p in "$@"; do
		[ -e "$p" ] || continue
		for f in $(git -C "$dir" apply --numstat "$p" | cut -f3); do
			restore "$dir" "$f"
		done
	done
}

# apply_patches DIR SAVED PATCH...: the patches, in order, onto the committed
# state of the files they touch; SAVED keeps them for the next build to undo
apply_patches() {
	local dir=$1 saved=$2 p
	shift 2
	unpatch "$dir" "$saved"/*.patch "$@"
	rm -rf "$saved"
	mkdir -p "$saved"
	for p in "$@"; do
		[ -e "$p" ] || continue
		git -C "$dir" apply --whitespace=nowarn "$p" || { echo "$(basename "$p") does not apply to $dir" >&2; exit 1; }
		cp "$p" "$saved/"
	done
	say "applied $# patches to $(basename "$(cd "$dir" && pwd)")"
}

# model_files SRC DIR LIST: the files under SRC copied into DIR, modes and
# times kept (OpenWrt's kernel stamp hashes the times of target/linux files);
# a file an earlier build copied (LIST) that SRC no longer has goes back
model_files() {
	local src=$1 dir=$2 list=$3 f
	(cd "$src" && find . ! -type d | sed 's|^\./||' | LC_ALL=C sort) >"$list.new"
	if [ -f "$list" ]; then
		LC_ALL=C comm -23 "$list" "$list.new" | while IFS= read -r f; do
			restore "$dir" "$f"
		done
	fi
	cp -rp "$src/." "$dir/"
	mv "$list.new" "$list"
}

# 1. OpenWrt main at the pinned commit
if [ ! -d "$W/.git" ]; then
	say "cloning OpenWrt into $W"
	mkdir -p "$(dirname "$W")"
	git clone "$OPENWRT_URL" "$W"
fi
cd "$W"
if [ "$(git rev-parse HEAD)" != "$OPENWRT_COMMIT" ]; then
	unpatch . "$W/.main-patches/openwrt/"*.patch "$MAIN"/patches/openwrt/*.patch
	git diff --quiet || { echo "$W has changes of its own and is not at $OPENWRT_COMMIT; build in a fresh directory" >&2; exit 1; }
	git fetch -q origin
	git checkout -q "$OPENWRT_COMMIT"
fi
say "OpenWrt $(git log -1 --format='%h %cd %s' --date=short)"

# 2. the devices' pull requests and the local patches
apply_patches . "$W/.main-patches/openwrt" "$MAIN"/patches/openwrt/*.patch

# 3. the board files: qca-wireless with the board-file pull requests on it,
# committed with a fixed committer and date, so the commit is QCA_COMMIT
Q=$W/.qca-wireless
[ -d "$Q/.git" ] || git clone -q "$QCA_URL" "$Q"
if [ "$(git -C "$Q" rev-parse -q --verify "$QCA_COMMIT^{commit}" || true)" != "$QCA_COMMIT" ]; then
	git -C "$Q" fetch -q origin
	git -C "$Q" fetch -q "$QCA_PR_URL" $QCA_PICKS
	git -C "$Q" checkout -q --detach "$QCA_BASE"
	for c in $QCA_PICKS; do
		GIT_COMMITTER_NAME="openwrt-arista build" GIT_COMMITTER_EMAIL=build@invalid \
			GIT_COMMITTER_DATE=$QCA_DATE git -C "$Q" cherry-pick "$c" >/dev/null
	done
	[ "$(git -C "$Q" rev-parse HEAD)" = "$QCA_COMMIT" ] ||
		{ echo "the combined board files are $(git -C "$Q" rev-parse HEAD), not $QCA_COMMIT" >&2; exit 1; }
fi
sed -i -e "s|^PKG_SOURCE_URL=.*|PKG_SOURCE_URL=file://$Q|" \
	-e "s|^PKG_SOURCE_DATE:=.*|PKG_SOURCE_DATE:=${QCA_DATE%%T*}|" \
	-e "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=$QCA_COMMIT|" \
	-e "s|^PKG_MIRROR_HASH:=.*|PKG_MIRROR_HASH:=skip|" package/firmware/ipq-wifi/Makefile
say "board files: qca-wireless ${QCA_COMMIT:0:12}"

# 4. the models' files, less what main or the pull requests have instead,
# then main's own versions
S=$W/.main-files.d
rm -rf "$S"
mkdir -p "$S"
for m in c360 c260 w318; do
	cp -rp "$HERE/$m/files/." "$S/"
done
rm -rf "$S/package/kernel/qca-nss-dp" \
	"$S/target/linux/qualcommax/files" \
	"$S"/target/linux/qualcommax/*/base-files/etc/hotplug.d/ieee80211 \
	"$S"/target/linux/qualcommax/*/base-files/etc/hotplug.d/firmware/12-ath11k-vendor-firmware \
	"$S/target/linux/qualcommax/ipq807x/base-files/etc/uci-defaults/14-arista-c360-leds-mgig" \
	"$S/target/linux/qualcommax/ipq807x/base-files/etc/init.d/arista-c360-linkwatch"
cp -rp "$MAIN/files/." "$S/"
model_files "$S" . .main-files
for f in target/linux/qualcommax/*/base-files/etc/init.d/* target/linux/qualcommax/*/base-files/usr/sbin/* \
	target/linux/qualcommax/*/base-files/etc/board.d/* \
	target/linux/qualcommax/*/base-files/usr/libexec/*; do
	[ -f "$f" ] && chmod 0755 "$f"
done
chmod 0644 target/linux/qualcommax/*/base-files/etc/hotplug.d/*/*

# 5. the feeds at their pinned commits
: >feeds.conf
for f in packages luci routing telephony video; do
	v=FEED_$f
	[ -n "${!v:-}" ] && echo "src-git $f ${!v}" >>feeds.conf
done
./scripts/feeds update -a >/dev/null
# the port's patches to a feed's packages (main/patches/feeds/<feed>/)
for f in feeds/*/; do
	f=$(basename "$f")
	[ -d "$MAIN/patches/feeds/$f" ] || [ -d "$W/.main-patches/feeds-$f" ] || continue
	apply_patches "feeds/$f" "$W/.main-patches/feeds-$f" "$MAIN/patches/feeds/$f/"*.patch
done
./scripts/feeds update -i >/dev/null
./scripts/feeds install squashfs-tools luci bluez curl >/dev/null
say "feeds: $(sed 's/^src-git \([a-z]*\) .*\^\(.\{8\}\).*/\1 \2/' feeds.conf | tr '\n' ' ')"

# 6. configure and build
cp "$MAIN/config/$SUB.seed" .config
make defconfig >/dev/null
for d in $DEVICES; do
	grep -q "^CONFIG_TARGET_DEVICE_qualcommax_${SUB}_DEVICE_$d=y" .config ||
		grep -q "^CONFIG_TARGET_qualcommax_${SUB}_DEVICE_$d=y" .config ||
		{ echo "$d is not selected after defconfig" >&2; exit 1; }
done
O=bin/targets/qualcommax/$SUB
rm -rf $O bin/packages
say "building $SUB (log: $W/build-$SUB.log)"
make -j"$(nproc)" IGNORE_ERRORS=m >build-$SUB.log 2>&1 ||
	{ tail -40 build-$SUB.log; echo "the build failed; see $W/build-$SUB.log" >&2; exit 1; }

# 7. collect: each model's images, and the subtarget's packages
mkdir -p "$OUT"
for m in $MODELS; do
	d=arista_${m:0:1}-${m:1}
	rm -rf "$OUT/$m"
	mkdir -p "$OUT/$m"
	cp $O/*"$d"[.-]* "$OUT/$m/"
done
rm -rf "$OUT/feed-$SUB"
for idx in $(find $O bin/packages -name packages.adb); do
	d=$(dirname "$idx")
	case $d in
	$O/*) rel=${d#$O/} ;;
	*) rel=${d#bin/packages/} ;;
	esac
	mkdir -p "$OUT/feed-$SUB/$rel"
	cp "$d"/*.apk "$d/packages.adb" "$OUT/feed-$SUB/$rel/"
done

# 8. checks and extras
if [ $SUB = ipq807x ]; then
	python3 "$HERE/c360/tools/check-initramfs.py" "$OUT"/c360/*arista_c-360-initramfs-uImage.itb distributable
	python3 "$HERE/c360/tools/c360-make-stick.py" --images "$OUT/c360" --img "$OUT/c360/c360-openwrt-installer.img" --xz >/dev/null
fi
(cd "$OUT" && find . -path ./feed-\* -prune -o -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum >SHA256SUMS)
failed=$(grep -cE 'ERROR: package/.* failed to build' build-$SUB.log || true)
say "done: $OUT ($MODELS); kernel $(grep -E '^kernel ' $O/*.manifest | head -1 | cut -d' ' -f3); $failed packages failed to build (see build-$SUB.log)"
