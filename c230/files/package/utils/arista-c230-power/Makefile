# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-c230-power
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-c230-power
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista C-230 PoE power policy (5 GHz chains, radio power, USB, Bluetooth on 802.3af)
  DEPENDS:=@TARGET_qualcommax_ipq807x +iw +iwinfo +jsonfilter +lldpd
  PKGARCH:=all
endef

define Package/arista-c230-power/description
  Reads which PoE class the Arista C-230's Ethernet 1 negotiated, and on
  802.3af power without a DC supply does as Arista's own system does: runs
  the 5 GHz radio on 2 of its 4 chains, caps the serving radios' transmit
  power, and turns the USB port and the Bluetooth controller off. On
  802.3at or DC everything runs at full power. Arista's system also turns
  the scan radio and the 5 GHz channel width down; this leaves them alone.
  The power a switch allocates by LLDP decides the class, and LLDP runs on
  both Ethernet ports.
endef

define Package/arista-c230-power/conffiles
/etc/config/arista-c230-power
endef

define Build/Compile
endef

define Package/arista-c230-power/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/etc/hotplug.d/net \
		$(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/arista-c230-power $(1)/usr/sbin/arista-c230-power
	$(INSTALL_BIN) ./files/arista-c230-power.init $(1)/etc/init.d/arista-c230-power
	$(INSTALL_CONF) ./files/arista-c230-power.config $(1)/etc/config/arista-c230-power
	$(INSTALL_DATA) ./files/arista-c230-power.hotplug $(1)/etc/hotplug.d/net/50-arista-c230-power
	$(INSTALL_DATA) ./files/arista-c230-power.lldpd $(1)/etc/uci-defaults/95-arista-c230-lldpd
endef

$(eval $(call BuildPackage,arista-c230-power))
