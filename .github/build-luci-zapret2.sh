#!/bin/bash
# Build the noarch luci-app-zapret2 IPK + APK from the repo tree (plain file
# copy — LuCI client views are shipped as-is). Runs once (architecture-independent).
#
# Usage: build-luci-zapret2.sh <version>

set -eo pipefail

PKG_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
SRC="$SCRIPT_DIR/../luci-app-zapret2"
OUT_DIR="$SCRIPT_DIR/out"
mkdir -p "$OUT_DIR"

DEPENDS="luci-base, zapret2"

BASE="$(mktemp -d)"
mkdir -p "$BASE/www"
cp -a "$SRC/htdocs/luci-static" "$BASE/www/luci-static"
cp -a "$SRC/root/." "$BASE/"

# shared postinst (clears LuCI caches, reloads rpcd/uhttpd)
POSTINST="$(mktemp)"
cat > "$POSTINST" <<'EOF'
#!/bin/sh
if [ -z "${IPKG_INSTROOT}" ]; then
	rm -f /tmp/luci-index*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload
	[ -f "/sbin/luci-reload" ] && /sbin/luci-reload
	[ -f "/etc/init.d/uhttpd" ] && /etc/init.d/uhttpd reload
fi
exit 0
EOF
chmod 755 "$POSTINST"

# ---- IPK (Architecture: all) ----
IPK="$(mktemp -d)"; cp -a "$BASE/." "$IPK/"
mkdir -p "$IPK/CONTROL"
cat > "$IPK/CONTROL/control" <<EOF
Package: luci-app-zapret2
Version: $PKG_VERSION
Architecture: all
Depends: $DEPENDS
Section: luci
Maintainer: remittor
License: MIT
URL: https://github.com/remittor/zapret-openwrt
Description: LuCI support for zapret2
EOF
install -m755 "$POSTINST" "$IPK/CONTROL/postinst"
fakeroot ipkg-build -m "" "$IPK" "$OUT_DIR"
rm -rf "$IPK"

# ---- APK (arch:noarch — arch:all is uninstallable on OpenWrt apk) ----
APK="$(mktemp -d)"; cp -a "$BASE/." "$APK/"
mkdir -p "$APK/lib/apk/packages"
find "$APK" -type f,l -printf '/%P\n' | sort > "$APK/lib/apk/packages/luci-app-zapret2.list"
apk mkpkg \
    --info "name:luci-app-zapret2" \
    --info "version:$PKG_VERSION" \
    --info "description:LuCI support for zapret2" \
    --info "arch:noarch" \
    --info "origin:luci-app-zapret2" \
    --info "url:https://github.com/remittor/zapret-openwrt" \
    --info "license:MIT" \
    --info "depends:$DEPENDS" \
    --script "post-install:$POSTINST" \
    --script "post-upgrade:$POSTINST" \
    ${APK_SIGN_KEY:+--sign-key "$APK_SIGN_KEY"} \
    --files "$APK" \
    --output "$OUT_DIR/luci-app-zapret2_${PKG_VERSION}_all.apk"
rm -rf "$APK" "$BASE" "$POSTINST"
echo "Done: luci-app-zapret2 (noarch)"
