# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-c260-bluetooth
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-c260-bluetooth
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista C-260 Bluetooth controller (CSR8811) bring-up
  DEPENDS:=@TARGET_qualcommax_ipq807x +bluez-utils +kmod-hci-uart +squashfs-tools-unsquashfs +ubi-utils
  PKGARCH:=all
endef

define Package/arista-c260-bluetooth/description
  Starts the Arista C-260's CSR8811 Bluetooth controller as Arista's own
  system does: its PS keys (ROM patches, UART settings, BD address) are
  loaded into the chip's RAM over BCSP, then it runs as an H4 controller
  (hci0) for BlueZ. The PS keys are copied from the unit's Arista system
  in NAND slot 1 the first time.
endef

define Build/Compile
endef

define Package/arista-c260-bluetooth/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d
	$(INSTALL_BIN) ./files/arista-c260-bluetooth $(1)/usr/sbin/arista-c260-bluetooth
	$(INSTALL_BIN) ./files/arista-c260-bluetooth.init $(1)/etc/init.d/arista-c260-bluetooth
endef

$(eval $(call BuildPackage,arista-c260-bluetooth))
