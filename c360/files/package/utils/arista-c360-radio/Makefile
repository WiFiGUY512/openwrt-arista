# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=arista-c360-radio
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/arista-c360-radio
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Arista C-360 radio plan (6 GHz or dual 5 GHz)
  DEPENDS:=@TARGET_qualcommax_ipq807x
  PKGARCH:=all
endef

define Package/arista-c360-radio/description
  Switches the Arista C-360 between Arista's two radio plans: 6 GHz (the
  IPQ8074 on 2.4 GHz and all of 5 GHz, the serving QCN9074 on 6 GHz) and
  dual 5 GHz (the IPQ8074 on lower 5 GHz, the serving QCN9074 on upper
  5 GHz), with the plan's gpio9 level, IPQ8074 calibration and board data.
endef

define Package/arista-c360-radio/conffiles
/etc/config/arista-c360-radio
endef

define Build/Compile
endef

define Package/arista-c360-radio/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) ./files/arista-c360-radio-mode $(1)/usr/sbin/arista-c360-radio-mode
	$(INSTALL_BIN) ./files/arista-c360-radio.init $(1)/etc/init.d/arista-c360-radio
	$(INSTALL_CONF) ./files/arista-c360-radio.config $(1)/etc/config/arista-c360-radio
endef

$(eval $(call BuildPackage,arista-c360-radio))
