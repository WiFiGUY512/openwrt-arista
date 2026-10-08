# The Arista C-360, for ../build.sh. Sourced from inside the OpenWrt tree.

MODEL_NAME="Arista C-360"
DEVICE=arista_c360
TARGET=qualcommax/ipq807x
# the feed packages the image needs beyond OpenWrt's core
FEEDS_INSTALL="squashfs-tools luci bluez proto-bonding"

# fix_modes: modes for files/ that git on some hosts does not keep
fix_modes() {
	local q=target/linux/qualcommax/ipq807x/base-files
	chmod 0755 $q/usr/sbin/arista-c360-wifi-fw $q/usr/sbin/arista-c360-install \
		$q/etc/init.d/arista-c360-ble $q/etc/init.d/arista-c360-linkwatch
	chmod 0644 $q/lib/preinit/81_arista_c360_wifi $q/etc/hotplug.d/ieee80211/12-arista-c360-leds
}

# after_build OUT: checks on the collected images, and the USB stick image
after_build() {
	local out=$1
	# the RAM installer holds the installer and can read the stick, and no
	# Arista file or calibration is baked in
	python3 "$MODEL_DIR/tools/check-initramfs.py" "$out"/*$DEVICE-initramfs-uImage.itb distributable
	# VXLAN and fallbacks install from the feed onto this kernel
	modules_fit "$out" kmod-vxlan kmod-veth kmod-nft-bridge
	python3 "$MODEL_DIR/tools/c360-make-stick.py" --images "$out" --img "$out/c360-openwrt-installer.img" --xz >/dev/null
}
