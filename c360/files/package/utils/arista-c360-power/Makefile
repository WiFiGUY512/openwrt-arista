# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-c360-power
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-c360-power
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista C-360 PoE power policy (USB off and radio caps on 802.3at)
  DEPENDS:=@TARGET_qualcommax_ipq807x +iw +iwinfo
  PKGARCH:=all
endef

define Package/arista-c360-power/description
  Reads which PoE class each input of the Arista C-360 negotiated, and on
  802.3at (or af) power alone does as Arista's own system does: turns the
  USB port off and caps the serving radios' transmit power.
endef

define Package/arista-c360-power/conffiles
/etc/config/arista-c360-power
endef

define Build/Compile
endef

define Package/arista-c360-power/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/etc/hotplug.d/net
	$(INSTALL_BIN) ./files/arista-c360-power $(1)/usr/sbin/arista-c360-power
	$(INSTALL_BIN) ./files/arista-c360-power.init $(1)/etc/init.d/arista-c360-power
	$(INSTALL_CONF) ./files/arista-c360-power.config $(1)/etc/config/arista-c360-power
	$(INSTALL_DATA) ./files/arista-c360-power.hotplug $(1)/etc/hotplug.d/net/50-arista-c360-power
endef

$(eval $(call BuildPackage,arista-c360-power))
