# SPDX-License-Identifier: GPL-2.0-only
#
# Open-Box 一体化透明代理(架构相关包):sing-box 内核 + musl Node 运行时 + 面板 +
# init 脚本 + /opt/open-box 运行时数据骨架。编译期从上游源码仓库
# https://github.com/liandu2024/Open-Box 现拉最新 main 构建(见 Build/Prepare)。
#
# 配套的 luci-app-openbox(架构无关包)负责 LuCI 兜底页三文件(menu.d/acl.d/status.js),
# 二者分别 BuildPackage,固件里同时勾选 CONFIG_PACKAGE_open-box=y 与
# CONFIG_PACKAGE_luci-app-openbox=y 即可。

include $(TOPDIR)/rules.mk

PKG_NAME:=open-box
# 包版本仅作 opkg/apk 升级对比用;产物 meta.json 里的真实版本在构建期自动取自
# 上游 panel/package.json。上游面板版本变化时请同步此值。
PKG_VERSION:=2.04
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_BUILD_PARALLEL:=0

include $(INCLUDE_DIR)/package.mk

# ---- 架构限制 ----
# 固件内置仅做 x86_64(用户决定,armv7/aarch64 不编译)。限制写在 DEPENDS:=@x86_64,
# 非 x86_64 在 menuconfig 里自动隐藏、绝不进入编译选项。
# 顶层【严禁】用 $(error) 拦截:make defconfig 时精简 .config 尚无 CONFIG_ARCH,
# include/scan.mk 以 DUMP=1 扫描包元数据时 $(ARCH) 为空,$(error) 会使本包元数据
# 输出失败、不进 tmp/.packageinfo,conf 随后把 .config 里的 CONFIG_PACKAGE_open-box=y
# 当未知符号静默丢弃(menuconfig 里也看不到)。
define Package/open-box
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Open-Box transparent proxy (sing-box core + panel)
  URL:=https://github.com/liandu2024/Open-Box
  DEPENDS:=@x86_64 +curl +ca-bundle
endef

define Package/open-box/description
  Open-Box is an all-in-one transparent proxy for OpenWrt: sing-box core,
  musl Node-based management panel, and init scripts. Source is pulled fresh
  from the upstream GitHub repository main branch at build time.
endef

# OpenWrt 架构 -> Open-Box 资产架构名(仅保留 x86_64 映射,空值守卫在 Build/Compile)
ifeq ($(ARCH),x86_64)
  OPENBOX_ARCH:=x64
endif

# ---- 依赖声明 ----
# 捆绑的 Alpine musl 库(DT_NEEDED 为 libc.musl-x86_64.so.1)以及 musl Node 二进制
# 自己的 DT_NEEDED 也带这个 soname;OpenWrt 的 musl soname 是 libc.so,打包期
# CheckDependencies 的扫描器不认 libc.musl-x86_64.so.1,需显式声明提供,否则报:
#   "Package open-box is missing dependencies ... libc.musl-x86_64.so.1"
# 运行时无碍:musl ldso 把 libc.* 前缀当保留名自解析。ipk/apk 两种格式都走同一套
# provides 机制,此钩子两边通用。
# 注意:define 体必须恰好一行、不留空行——它被展开进反斜杠续行的 @( … ) | sort
# 子 shell 块,多余换行会截断续行导致语法错误。
define Package/open-box/extra_provides
echo "libc.musl-x86_64.so.1"
endef

# ---- 构建期:现拉上游最新源码(绕过 OpenWrt 下载缓存),并把本包 build 脚本拷进构建目录 ----
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	rm -rf $(PKG_BUILD_DIR)/src
	git clone --depth 1 https://github.com/liandu2024/Open-Box $(PKG_BUILD_DIR)/src
	cp $(CURDIR)/files/build-openbox.sh $(PKG_BUILD_DIR)/build-openbox.sh
endef

# ---- 组装 /opt/open-box 内容(stage),由 Package/install 铺到 $(1)/opt/open-box ----
define Build/Compile
	@[ -n "$(OPENBOX_ARCH)" ] || { echo "ERROR: open-box 仅支持 x86_64架构"; exit 1; }
	$(SHELL) $(PKG_BUILD_DIR)/build-openbox.sh "$(OPENBOX_ARCH)" "$(PKG_BUILD_DIR)/src" "$(PKG_BUILD_DIR)/stage" "$(DL_DIR)"
endef

define Package/open-box/install
	$(INSTALL_DIR) $(1)/opt/open-box/data $(1)/etc/init.d
	$(CP) $(PKG_BUILD_DIR)/stage/node $(1)/opt/open-box/
	$(CP) $(PKG_BUILD_DIR)/stage/panel $(1)/opt/open-box/
	$(INSTALL_DIR) $(1)/opt/open-box/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/stage/bin/sing-box $(1)/opt/open-box/bin/sing-box
	$(CP) $(PKG_BUILD_DIR)/stage/openwrt $(1)/opt/open-box/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/stage/meta.json $(1)/opt/open-box/meta.json
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/stage/uninstall.sh $(1)/opt/open-box/uninstall.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/stage/update.sh $(1)/opt/open-box/update.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/stage/openwrt/initd/openbox $(1)/etc/init.d/openbox
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/stage/openwrt/initd/openbox-panel $(1)/etc/init.d/openbox-panel

	# 面板开机自启:直接打进 S98 软链。固件内置时 postinst 的 enable 会因 IPKG_INSTROOT
	# 非空被跳过而失效,软链随包安装是唯一可靠做法;内核 openbox 不自启,由用户配置后启动。
	$(INSTALL_DIR) $(1)/etc/rc.d
	$(LN) ../init.d/openbox-panel $(1)/etc/rc.d/S98openbox-panel
endef

$(eval $(call BuildPackage,open-box))