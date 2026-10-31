include $(TOPDIR)/rules.mk

PKG_NAME:=dfs-look
PKG_VERSION:=0.1
PKG_RELEASE:=5
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/dfs-look
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Move a 5 GHz radio to a DFS channel only after a look
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-uloop +ucode-mod-ubus +ucode-mod-nl80211 +ucode-mod-socket
  PKGARCH:=all
endef

define Package/dfs-look/description
 A 5 GHz radio on an automatic channel starts outside DFS channels (wifi-scripts'
 dfs_look_first, on by default), so it serves at once. dfs-look then looks at
 every 5 GHz channel, with the board's scan radio where airscan has one, and
 moves the radio to a DFS block, by hostapd's CHAN_SWITCH and a radar check
 there, only where that block is clearly better than its own and than the best
 outside DFS.
endef

define Build/Compile
endef

define Package/dfs-look/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d
	$(INSTALL_BIN) ./files/dfs-look.uc $(1)/usr/sbin/dfs-look
	$(INSTALL_BIN) ./files/dfs-look.init $(1)/etc/init.d/dfs-look
endef

$(eval $(call BuildPackage,dfs-look))
