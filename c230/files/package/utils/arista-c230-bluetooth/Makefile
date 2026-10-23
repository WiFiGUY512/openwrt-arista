# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-c230-bluetooth
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-c230-bluetooth
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista C-230 Bluetooth controller (CSR8811) bring-up
  DEPENDS:=@TARGET_qualcommax_ipq807x +bluez-utils +bluez-utils-extra +kmod-hci-uart \
	+squashfs-tools-unsquashfs +ubi-utils
  PKGARCH:=all
endef

define Package/arista-c230-bluetooth/description
  Starts the Arista C-230's CSR8811 Bluetooth controller as on the C-260:
  its PS keys (ROM patches, UART settings, BD address) are loaded into the
  chip's RAM over BCSP, then it runs as an H4 controller (hci0) for BlueZ.
  The PS keys are copied from the unit's Arista system in NAND slot 1 the
  first time, where it has them; otherwise they go in /lib/firmware by hand.
endef

define Build/Compile
endef

define Package/arista-c230-bluetooth/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d
	$(INSTALL_BIN) ./files/arista-c230-bluetooth $(1)/usr/sbin/arista-c230-bluetooth
	$(INSTALL_BIN) ./files/arista-c230-bluetooth.init $(1)/etc/init.d/arista-c230-bluetooth
endef

$(eval $(call BuildPackage,arista-c230-bluetooth))
