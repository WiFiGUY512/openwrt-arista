# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-c260-power
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-c260-power
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista C-260 PoE power policy (radio power and Bluetooth on 802.3at)
  DEPENDS:=@TARGET_qualcommax_ipq807x +iw +iwinfo +jsonfilter +lldpd
  PKGARCH:=all
endef

define Package/arista-c260-power/description
  Reads which PoE class Ethernet 1 of the Arista C-260 negotiated, and on
  802.3at (or af) power without a DC supply does as Arista's own system
  does: caps the serving radios' transmit power and turns the Bluetooth
  controller off. Arista's system also turns the scan radio's power down;
  this leaves the scan radio alone. The power a switch allocates by LLDP
  decides the class, and LLDP runs on both Ethernet ports.
endef

define Package/arista-c260-power/conffiles
/etc/config/arista-c260-power
endef

define Build/Compile
endef

define Package/arista-c260-power/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/etc/hotplug.d/net \
		$(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/arista-c260-power $(1)/usr/sbin/arista-c260-power
	$(INSTALL_BIN) ./files/arista-c260-power.init $(1)/etc/init.d/arista-c260-power
	$(INSTALL_CONF) ./files/arista-c260-power.config $(1)/etc/config/arista-c260-power
	$(INSTALL_DATA) ./files/arista-c260-power.hotplug $(1)/etc/hotplug.d/net/50-arista-c260-power
	$(INSTALL_DATA) ./files/arista-c260-power.lldpd $(1)/etc/uci-defaults/95-arista-c260-lldpd
endef

$(eval $(call BuildPackage,arista-c260-power))
