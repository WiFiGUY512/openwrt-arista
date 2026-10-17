# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-w318-power
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-w318-power
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista W-318 PoE power policy (USB, radio power, PoE output)
  DEPENDS:=@TARGET_qualcommax_ipq60xx +iw +iwinfo +lldpd
  PKGARCH:=all
endef

define Package/arista-w318-power/description
  Reads which PoE class the uplink of the Arista W-318 negotiated, and on
  802.3at (or af) power without a DC supply does as Arista's own system
  does: cuts the USB port's power and caps the radios' transmit power.
  Network 1's PoE output is on only when the W-318 itself runs on 802.3bt.
  The power a switch allocates by LLDP decides the class, and LLDP runs on
  the uplink.
endef

define Package/arista-w318-power/conffiles
/etc/config/arista-w318-power
endef

define Build/Compile
endef

define Package/arista-w318-power/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/etc/hotplug.d/net \
		$(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/arista-w318-power $(1)/usr/sbin/arista-w318-power
	$(INSTALL_BIN) ./files/arista-w318-power.init $(1)/etc/init.d/arista-w318-power
	$(INSTALL_CONF) ./files/arista-w318-power.config $(1)/etc/config/arista-w318-power
	$(INSTALL_DATA) ./files/arista-w318-power.hotplug $(1)/etc/hotplug.d/net/50-arista-w318-power
	$(INSTALL_DATA) ./files/arista-w318-power.lldpd $(1)/etc/uci-defaults/95-arista-w318-lldpd
endef

$(eval $(call BuildPackage,arista-w318-power))
