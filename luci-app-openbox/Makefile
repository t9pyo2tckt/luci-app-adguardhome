# SPDX-License-Identifier: GPL-2.0-only
#
# Open-Box LuCI 兜底页(架构无关包):面板打不开时,从路由器自带界面一键停代理、
# 恢复直连。只携带三个静态文件(menu.d / acl.d / status.js),无后端 Lua 代码,
# 因此用普通 package 而非 luci.mk;PKGARCH:=all 使其跨架构通用。
#
# 依赖 open-box 包(提供 /opt/open-box 运行时与 init 脚本)。固件里需同时勾选
# CONFIG_PACKAGE_luci-app-openbox=y 与 CONFIG_PACKAGE_open-box=y。

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openbox
# 与 open-box 包版本保持一致(跟随上游面板版本)
PKG_VERSION:=2.04
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_ARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-openbox
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Applications
  TITLE:=Open-Box LuCI fallback page
  URL:=https://github.com/liandu2024/Open-Box
  DEPENDS:=+luci-base +open-box
  PKGARCH:=all
endef

define Package/luci-app-openbox/description
  LuCI fallback page for Open-Box: start/stop the panel & sing-box core,
  toggle their autostart, and emergency-stop to restore direct connection.
endef

# 三个静态文件相对本包目录 root/ 展开到目标文件系统:
#   menu.d  -> /usr/share/luci/menu.d/luci-app-openbox.json
#   acl.d   -> /usr/share/rpcd/acl.d/luci-app-openbox.json
#   status.js -> /www/luci-static/resources/view/openbox/status.js
define Package/luci-app-openbox/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d \
		$(1)/usr/share/rpcd/acl.d \
		$(1)/www/luci-static/resources/view/openbox
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-openbox.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-openbox.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/openbox/status.js $(1)/www/luci-static/resources/view/openbox/
endef

$(eval $(call BuildPackage,luci-app-openbox))