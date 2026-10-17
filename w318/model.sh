# The Arista W-318, for ../build.sh, which sources it; its functions run inside
# the OpenWrt tree.

MODEL_NAME="Arista W-318"
DEVICE=arista_w318
TARGET=qualcommax/ipq60xx
# the feed packages the image needs beyond OpenWrt's core
FEEDS_INSTALL="squashfs-tools luci bluez"

# fix_modes: modes for files/ that git on some hosts does not keep
fix_modes() {
	local q=target/linux/qualcommax/ipq60xx/base-files
	chmod 0644 $q/etc/hotplug.d/firmware/12-ath11k-vendor-firmware \
		$q/etc/hotplug.d/firmware/13-arista-w318-board-data \
		$q/etc/hotplug.d/ieee80211/12-arista-w318-leds
	chmod 0755 $q/etc/init.d/arista-w318-ble $q/etc/init.d/arista-w318-board-data \
		$q/etc/init.d/arista-w318-lanled $q/usr/libexec/arista-w318-lanled \
		$q/usr/sbin/arista-w318-install \
		package/utils/arista-w318-power/files/arista-w318-power \
		package/utils/arista-w318-power/files/arista-w318-power.init
}

# after_build OUT: checks on the collected images
after_build() {
	local out=$1 p
	ls -l "$out"/*$DEVICE-initramfs-uImage.itb "$out"/*$DEVICE-squashfs-sysupgrade.bin
	# the QCN9072 card's driver, Bluetooth, the TPM and the power policy
	for p in kmod-ath11k-pci kmod-hci-uart bluez-utils-extra kmod-tpm-tis-spi \
		squashfs-tools-unsquashfs arista-w318-power; do
		grep -q "^$p " "$out"/*$DEVICE.manifest || { echo "$p is not in the image" >&2; exit 1; }
	done
	# modules an add-on may install (VXLAN, veth, bridge filtering) are in
	# the feed, built for this kernel
	modules_fit "$out" kmod-vxlan kmod-veth kmod-nft-bridge
}
