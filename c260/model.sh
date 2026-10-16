# The Arista C-260, for ../build.sh. Sourced from inside the OpenWrt tree.

MODEL_NAME="Arista C-260"
DEVICE=arista_c260
TARGET=qualcommax/ipq807x
# the feed packages the image needs beyond OpenWrt's core
FEEDS_INSTALL="squashfs-tools luci bluez"

# fix_modes: modes for files/ that git on some hosts does not keep
fix_modes() {
	chmod 0644 target/linux/qualcommax/ipq807x/base-files/etc/hotplug.d/firmware/13-arista-c260-board-data
	chmod 0755 package/utils/arista-c260-bluetooth/files/arista-c260-bluetooth \
		package/utils/arista-c260-bluetooth/files/arista-c260-bluetooth.init
}

# after_build OUT: checks on the collected images
after_build() {
	local out=$1 p
	ls -l "$out"/*$DEVICE-initramfs-uImage.itb "$out"/*$DEVICE-squashfs-factory.ubi \
		"$out"/*$DEVICE-squashfs-sysupgrade.bin
	# the QCA988x radio's driver and firmware, and the Bluetooth bring-up
	for p in kmod-ath10k-ct ath10k-firmware-qca988x-ct arista-c260-bluetooth; do
		grep -q "^$p " "$out"/*$DEVICE.manifest || { echo "$p is not in the image" >&2; exit 1; }
	done
}
