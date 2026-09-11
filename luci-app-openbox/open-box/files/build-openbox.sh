#!/bin/sh
# Open-Box OpenWrt 编译期打包脚本,由 open-box 包的 Build/Compile 调用。
#
# 用法: sh build-openbox.sh <x64> <srcroot> <outdir> <dldir>
#   srcroot = Build/Prepare 阶段 `git clone --depth 1` 得到的 liandu2024/Open-Box 源码根
#   outdir  = 组装出的 /opt/open-box 内容(stage,不解 tar),由 Makefile 的
#             Package/open-box/install 直接铺到 $(1)/opt/open-box
#   dldir   = 本包 Makefile 传入的 $(DL_DIR);musl Node / sing-box / Alpine apk
#             下载后缓存于此并做 SHA256 校验(命中缓存也校验)
#
# 版本号与各资产 SHA256 一律在本脚本构建期从 srcroot/scripts/build-release.sh 里
# sed 现取——上游只维护那一份,本脚本绝不硬编码版本/哈希,避免与上游漂移。

set -eu

[ "$#" -eq 4 ] || { echo "usage: $0 <x64> <srcroot> <outdir> <dldir>" >&2; exit 1; }
ARCH="$1"
SRCROOT="$2"
OUTDIR="$3"
DLDIR="$4"

case "$ARCH" in
  x64)
    SINGBOX_ARCH="amd64"
    ALPINE_ARCH="x86_64"
    NODE_SHA_VAR="NODE_SHA256_X64"
    SINGBOX_SHA_VAR="SINGBOX_SHA256_AMD64"
    LIBSTDCPP_SHA_VAR="ALPINE_LIBSTDCPP_SHA256_X86_64"
    LIBGCC_SHA_VAR="ALPINE_LIBGCC_SHA256_X86_64"
    ;;
  *)
    echo "ERROR: 仅支持 x64(本包为 x86_64 专用)" >&2
    exit 1
    ;;
esac

# 安全边界:OUTDIR/DLDIR 不许为空或根,防止 rm -rf 炸穿
case "$OUTDIR" in ''|/|./) echo "ERROR: 非法 OUTDIR" >&2; exit 1 ;; esac
case "$SRCROOT" in ''|/) echo "ERROR: 非法 SRCROOT" >&2; exit 1 ;; esac

RELEASE_SH="$SRCROOT/scripts/build-release.sh"
[ -f "$RELEASE_SH" ] || { echo "ERROR: 找不到 $RELEASE_SH" >&2; exit 1; }

# ---- 从上游 build-release.sh 现取版本与哈希 ----
getvar() {
  sed -n "s/^$1=\"\([^\"]*\)\".*/\1/p" "$RELEASE_SH" | head -n 1
}
NODE_VERSION=$(getvar NODE_VERSION)
SINGBOX_VERSION=$(getvar SINGBOX_VERSION)
ALPINE_GCC_PKG_VERSION=$(getvar ALPINE_GCC_PKG_VERSION)
NODE_SHA256=$(getvar "$NODE_SHA_VAR")
SINGBOX_SHA256=$(getvar "$SINGBOX_SHA_VAR")
ALPINE_LIBSTDCPP_SHA256=$(getvar "$LIBSTDCPP_SHA_VAR")
ALPINE_LIBGCC_SHA256=$(getvar "$LIBGCC_SHA_VAR")

for v in NODE_VERSION SINGBOX_VERSION ALPINE_GCC_PKG_VERSION \
         NODE_SHA256 SINGBOX_SHA256 ALPINE_LIBSTDCPP_SHA256 ALPINE_LIBGCC_SHA256; do
  eval "val=\$$v"
  [ -n "$val" ] || { echo "ERROR: 从 build-release.sh 解析 $v 失败" >&2; exit 1; }
done

# 面板版本直接取自 panel/package.json,写进 meta.json 供面板与 LuCI 展示
PANEL_VERSION=$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' "$SRCROOT/panel/package.json" | head -n 1)
[ -n "$PANEL_VERSION" ] || PANEL_VERSION="unknown"

log() { echo "[open-box-build] $*" >&2; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 构建机(ubuntu)必有 curl;不做 wget 兼容分支保持脚本简洁
command -v curl >/dev/null 2>&1 || { echo "ERROR: 需要 curl(curl 未找到)" >&2; exit 1; }

# 下载到 $(DL_DIR) 缓存:SHA256 校验,含缓存命中时也校验——缓存被污染就拒用。
fetch_cached() {
  url="$1"; dest="$2"; label="$3"; expected="$4"
  if [ -s "$dest" ]; then
    log "命中缓存: $label ($(basename -- "$dest"))"
  else
    mkdir -p "$(dirname -- "$dest")"
    log "下载: $label"
    tmp="$dest.part"
    rm -f "$tmp"
    curl -fsSL --retry 3 -o "$tmp" "$url" || { rm -f "$tmp"; echo "ERROR: 下载失败: $label ($url)" >&2; exit 1; }
    mv "$tmp" "$dest"
  fi
  actual=$(sha256_of "$dest")
  [ "$actual" = "$expected" ] || {
    rm -f "$dest"
    echo "ERROR: $label 的 sha256 不匹配(期望 $expected,实际 $actual),已删除缓存文件" >&2
    exit 1
  }
}

# 清空本次输出目录,避免半成品残留
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

# ---------- 1. 自举 node/corepack 并构建前端 + server ----------
# 这里给“构建机”用的是 glibc 版官方 Node(跑 pnpm/vite),不是给路由器用的 musl 版。
if ! command -v node >/dev/null 2>&1 || ! command -v corepack >/dev/null 2>&1; then
  log "构建机缺少 node/corepack,下载官方 linux-x64 Node $NODE_VERSION 自举..."
  BOOT_NODE_TARBALL="node-v${NODE_VERSION}-linux-x64.tar.xz"
  BOOT_NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${BOOT_NODE_TARBALL}"
  BOOT_DIR="$OUTDIR/.node-bootstrap"
  mkdir -p "$BOOT_DIR"
  curl -fsSL --retry 3 -o "$BOOT_DIR/$BOOT_NODE_TARBALL" "$BOOT_NODE_URL" || \
    { echo "ERROR: 自举 Node 下载失败" >&2; exit 1; }
  tar -xJf "$BOOT_DIR/$BOOT_NODE_TARBALL" -C "$BOOT_DIR"
  BOOT_NODE_INNER=$(find "$BOOT_DIR" -maxdepth 1 -type d -name "node-v${NODE_VERSION}-linux-x64" | head -n 1)
  [ -n "$BOOT_NODE_INNER" ] || { echo "ERROR: 自举 Node 解包布局异常" >&2; exit 1; }
  export PATH="$BOOT_NODE_INNER/bin:$PATH"
fi

command -v node >/dev/null 2>&1 || { echo "ERROR: 无法取得 node" >&2; exit 1; }
command -v corepack >/dev/null 2>&1 || { echo "ERROR: 无法取得 corepack" >&2; exit 1; }

# corepack pnpm 会按 panel/package.json 的 packageManager 取定 pnpm 版本
log "corepack pnpm install(panel 依赖)..."
(cd "$SRCROOT/panel" && corepack pnpm install --frozen-lockfile)

log "构建前端 (vite build)..."
(cd "$SRCROOT/panel" && corepack pnpm run build)
mkdir -p "$OUTDIR/panel"
cp -R "$SRCROOT/panel/dist" "$OUTDIR/panel/dist"

log "pnpm deploy 出自包含 server..."
(cd "$SRCROOT/panel" && corepack pnpm --filter=./server deploy --prod "$OUTDIR/panel/server")

# ---------- 2. 下载并解出 musl Node 运行时(给路由器用) ----------
# 关键:OpenWrt 用 musl libc,官方 nodejs.org 的 linux-x64/arm64 是 glibc 链接,
# 上路由器起不来;必须用 unofficial-builds 的 musl 构建。
NODE_TARBALL="node-v${NODE_VERSION}-linux-${ARCH}-musl.tar.xz"
NODE_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/${NODE_TARBALL}"
NODE_CACHE="$DLDIR/$NODE_TARBALL"
fetch_cached "$NODE_URL" "$NODE_CACHE" "musl Node $NODE_VERSION ($ARCH)" "$NODE_SHA256"

log "解出 musl Node 运行时..."
NODE_EXTRACT="$OUTDIR/.node-extract"
mkdir -p "$NODE_EXTRACT"
tar -xJf "$NODE_CACHE" -C "$NODE_EXTRACT"
NODE_INNER=$(find "$NODE_EXTRACT" -maxdepth 1 -type d -name "node-v${NODE_VERSION}-linux-${ARCH}-musl" | head -n 1)
[ -f "$NODE_INNER/bin/node" ] || { echo "ERROR: Node tarball 布局异常,未找到 bin/node" >&2; exit 1; }

# 只留运行时真正需要的 bin/node + LICENSE(include/npm/corepack/share 全砍,省 ~80MB flash)
mkdir -p "$OUTDIR/node/bin" "$OUTDIR/node/lib"
cp "$NODE_INNER/bin/node" "$OUTDIR/node/bin/node"
chmod +x "$OUTDIR/node/bin/node"
[ -f "$NODE_INNER/LICENSE" ] && cp "$NODE_INNER/LICENSE" "$OUTDIR/node/LICENSE"
rm -rf "$NODE_EXTRACT"

# ---------- 3. 下载并解出 Alpine 的 musl libstdc++ / libgcc ----------
# x64 的 musl Node 动态依赖 libstdc++.so.6 / libgcc_s.so.1(DT_NEEDED),OpenWrt 默认
# 镜像不带 libstdcpp,面板会被 procd 无限重启。apk 包本质是 gzip 的 tar,直接解出 usr/lib。
ALPINE_LIBSTDCPP_PKG="libstdc++-${ALPINE_GCC_PKG_VERSION}.apk"
ALPINE_LIBGCC_PKG="libgcc-${ALPINE_GCC_PKG_VERSION}.apk"
ALPINE_BASE_URL="https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/${ALPINE_ARCH}"
ALPINE_LIBSTDCPP_CACHE="$DLDIR/alpine-${ALPINE_ARCH}-${ALPINE_LIBSTDCPP_PKG}"
ALPINE_LIBGCC_CACHE="$DLDIR/alpine-${ALPINE_ARCH}-${ALPINE_LIBGCC_PKG}"
fetch_cached "$ALPINE_BASE_URL/$ALPINE_LIBSTDCPP_PKG" "$ALPINE_LIBSTDCPP_CACHE" "Alpine libstdc++ ($ALPINE_ARCH)" "$ALPINE_LIBSTDCPP_SHA256"
fetch_cached "$ALPINE_BASE_URL/$ALPINE_LIBGCC_PKG" "$ALPINE_LIBGCC_CACHE" "Alpine libgcc ($ALPINE_ARCH)" "$ALPINE_LIBGCC_SHA256"

log "解出 Alpine musl libstdc++ / libgcc..."
ALPINE_EXTRACT="$OUTDIR/.alpine-extract"
mkdir -p "$ALPINE_EXTRACT"
tar -xzf "$ALPINE_LIBSTDCPP_CACHE" -C "$ALPINE_EXTRACT" usr/lib/
tar -xzf "$ALPINE_LIBGCC_CACHE" -C "$ALPINE_EXTRACT" usr/lib/
# -P 保留符号链接本身(libstdc++.so.6 -> libstdc++.so.6.0.x),不展开成两份拷贝
cp -P "$ALPINE_EXTRACT"/usr/lib/libstdc++.so.6* "$OUTDIR/node/lib/"
cp -P "$ALPINE_EXTRACT"/usr/lib/libgcc_s.so.1* "$OUTDIR/node/lib/"
rm -rf "$ALPINE_EXTRACT"

# ---------- 4. 下载并解出 sing-box(注意 x64 -> amd64;必须 -musl 静态资产) ----------
SINGBOX_TARBALL="sing-box-${SINGBOX_VERSION}-linux-${SINGBOX_ARCH}-musl.tar.gz"
SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${SINGBOX_TARBALL}"
SINGBOX_CACHE="$DLDIR/$SINGBOX_TARBALL"
fetch_cached "$SINGBOX_URL" "$SINGBOX_CACHE" "sing-box $SINGBOX_VERSION ($SINGBOX_ARCH)" "$SINGBOX_SHA256"

log "解出 sing-box..."
SINGBOX_EXTRACT="$OUTDIR/.singbox-extract"
mkdir -p "$SINGBOX_EXTRACT"
tar -xzf "$SINGBOX_CACHE" -C "$SINGBOX_EXTRACT"
SINGBOX_BIN=$(find "$SINGBOX_EXTRACT" -type f -name sing-box | head -n 1)
[ -n "$SINGBOX_BIN" ] || { echo "ERROR: sing-box tarball 里找不到 sing-box" >&2; exit 1; }
mkdir -p "$OUTDIR/bin"
cp "$SINGBOX_BIN" "$OUTDIR/bin/sing-box"
chmod +x "$OUTDIR/bin/sing-box"
rm -rf "$SINGBOX_EXTRACT"

# ---------- 5. 构建期依赖守卫(有 python3 才跑,缺失跳过) ----------
# 上游 scripts/dt-needed.py 是纯 Python 手工解析 ELF 程序头,不依赖 readelf/pyelftools。
if command -v python3 >/dev/null 2>&1; then
  log "校验 node DT_NEEDED..."
  NODE_NEEDED=$(python3 "$SRCROOT/scripts/dt-needed.py" "$OUTDIR/node/bin/node") || \
    { echo "ERROR: 解析 node DT_NEEDED 失败" >&2; exit 1; }
  BAD=""
  oldIFS=$IFS
  IFS='
'
  set -f
  for lib in $NODE_NEEDED; do
    case "$lib" in
      libc.musl-*|libc.so|libgcc_s.so.1) ;;
      *) [ -e "$OUTDIR/node/lib/$lib" ] || BAD="$BAD $lib" ;;
    esac
  done
  set +f
  IFS=$oldIFS
  [ -z "$BAD" ] || { echo "ERROR: node($ARCH) 缺少未捆绑的动态依赖:$BAD" >&2; exit 1; }

  log "校验 sing-box 静态链接..."
  python3 "$SRCROOT/scripts/dt-needed.py" --assert-static "$OUTDIR/bin/sing-box" || exit 1
else
  log "未找到 python3,跳过依赖守卫(如需守卫请安装 python3)"
fi

# ---------- 6. 拷贝 openwrt/(initd + luci)、uninstall.sh、update.sh ----------
# /opt/open-box 里保留 openwrt/initd 与 openwrt/luci,是 install.sh/update.sh 的
# 自引用来源(升级会从 /opt/open-box/openwrt/initd 重铺 /etc/init.d)。
log "拷贝 openwrt/ init + luci 与脚本..."
mkdir -p "$OUTDIR/openwrt"
cp -R "$SRCROOT/openwrt/initd" "$OUTDIR/openwrt/initd"
cp -R "$SRCROOT/openwrt/luci" "$OUTDIR/openwrt/luci"
cp "$SRCROOT/scripts/uninstall.sh" "$OUTDIR/uninstall.sh"
chmod +x "$OUTDIR/uninstall.sh"
cp "$SRCROOT/scripts/update.sh" "$OUTDIR/update.sh"
chmod +x "$OUTDIR/update.sh"

# ---------- 7. meta.json ----------
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$OUTDIR/meta.json" <<EOF
{
  "version": "$PANEL_VERSION",
  "singboxVersion": "$SINGBOX_VERSION",
  "nodeVersion": "$NODE_VERSION",
  "arch": "$ARCH",
  "builtAt": "$BUILT_AT"
}
EOF

# 清理构建期临时目录
rm -rf "$OUTDIR/.node-bootstrap"

log "完成: $OUTDIR(node/$PANEL_VERSION, sing-box $SINGBOX_VERSION, node $NODE_VERSION)"