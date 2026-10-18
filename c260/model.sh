# The Arista C-260, for ../build.sh, which sources it; its functions run inside
# the OpenWrt tree.

MODEL_NAME="Arista C-260"
DEVICE=arista_c260
TARGET=qualcommax/ipq807x
# the feed packages the image needs beyond OpenWrt's core
FEEDS_INSTALL="squashfs-tools luci bluez proto-bonding"

# fix_modes: modes for files/ that git on some hosts does not keep
fix_modes() {
	chmod 0644 target/linux/qualcommax/ipq807x/base-files/etc/hotplug.d/firmware/13-arista-c260-board-data \
		target/linux/qualcommax/ipq807x/base-files/etc/hotplug.d/ieee80211/12-arista-c260-leds
	chmod 0755 package/utils/arista-c260-bluetooth/files/arista-c260-bluetooth \
		package/utils/arista-c260-bluetooth/files/arista-c260-bluetooth.init \
		package/utils/arista-c260-power/files/arista-c260-power \
		package/utils/arista-c260-power/files/arista-c260-power.init \
		target/linux/qualcommax/ipq807x/base-files/etc/init.d/arista-c260-board-data \
		target/linux/qualcommax/ipq807x/base-files/usr/sbin/arista-c260-net
}

# after_build OUT: checks on the collected images
after_build() {
	local out=$1 p
	ls -l "$out"/*$DEVICE-initramfs-uImage.itb "$out"/*$DEVICE-squashfs-factory.ubi \
		"$out"/*$DEVICE-squashfs-sysupgrade.bin
	# the QCA988x radio's driver and firmware, the Bluetooth bring-up, airscan
	# and the power policy
	for p in kmod-ath10k-ct ath10k-firmware-qca988x-ct arista-c260-bluetooth airscan \
		arista-c260-power; do
		grep -q "^$p " "$out"/*$DEVICE.manifest || { echo "$p is not in the image" >&2; exit 1; }
	done
	# modules an add-on may install (VXLAN, veth, bridge filtering) are in
	# the feed, built for this kernel
	modules_fit "$out" kmod-vxlan kmod-veth kmod-nft-bridge
}
