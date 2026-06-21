#!/bin/bash
# Assemble the FULL zapret2 IPK + APK from bol-van's prebuilt static binaries
# (no SDK compile). Mirrors the ByeDPI-OpenWrt approach: one CPU-family binary
# set is repackaged for several OpenWrt arch tags. The install layout, conffiles
# and control scripts faithfully follow remittor's zapret2/Makefile.
#
# Usage: build-zapret2.sh <version> <embedded_dir> <bin_subdir> <"ow_arch1 ow_arch2 ...">
#   version      package version, e.g. 1.0.2
#   embedded_dir extracted root of zapret2-vX-openwrt-embedded.tar.gz
#                (the inner "zapret2-vX" dir: binaries/, common/, lua/, files/,
#                 ipset/, blockcheck2.d/, blockcheck2.sh, init.d/, config.default)
#   bin_subdir   prebuilt binary family, e.g. linux-arm64 / linux-mipsel
#   ow_arches    space-separated OpenWrt arch strings the binary is valid for

set -eo pipefail

PKG_VERSION="$1"
EMB="$2"
BIN_SUBDIR="$3"
OPENWRT_ARCHES="$4"

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
CTRL="$SCRIPT_DIR/control"
PKGSRC="$SCRIPT_DIR/../zapret2"      # repo's OpenWrt glue (init.d.sh, *.sh, config.default, ipset/*.txt, custom.d/)
OUT_DIR="$SCRIPT_DIR/out"
ZD="opt/zapret2"                     # install prefix inside the package
mkdir -p "$OUT_DIR"

BINDIR="$EMB/binaries/$BIN_SUBDIR"
for b in nfqws2 ip2net mdig; do
    [ -f "$BINDIR/$b" ] || { echo "ERROR: missing prebuilt $BIN_SUBDIR/$b"; ls -la "$BINDIR" || true; exit 1; }
done

# Conffiles (relative to /), one per line. Empty placeholders are created for
# any that have no source file (cust*.txt, extra custom.d scripts, auto hosts).
CONFFILES="$(cat "$CTRL/conffiles")"

# DEPENDS — kept identical to remittor's Makefile (LUA_JIT=1 => no lua dep).
PKG_DEPENDS="nftables, curl, gzip, coreutils, coreutils-sort, coreutils-sleep, kmod-nft-nat, kmod-nft-offload, kmod-nft-queue, libnetfilter-queue, libmnl, libcap, zlib"

stage_base() {
    local D="$1"
    # --- prebuilt binaries (static, from bol-van) ---
    install -Dm755 "$BINDIR/nfqws2" "$D/$ZD/nfq2/nfqws2"
    install -Dm755 "$BINDIR/ip2net" "$D/$ZD/ip2net/ip2net"
    install -Dm755 "$BINDIR/mdig"   "$D/$ZD/mdig/mdig"
    # --- runtime trees from the embedded tarball ---
    for d in common lua files ipset blockcheck2.d; do
        mkdir -p "$D/$ZD/$d"; cp -a "$EMB/$d/." "$D/$ZD/$d/"
    done
    install -Dm755 "$EMB/blockcheck2.sh" "$D/$ZD/blockcheck2.sh"
    mkdir -p "$D/$ZD/init.d"; cp -a "$EMB/init.d/." "$D/$ZD/init.d/"
    install -Dm755 "$EMB/init.d/openwrt/90-zapret2" "$D/etc/hotplug.d/iface/90-zapret2"
    mkdir -p "$D/$ZD/tmp"
    # --- repo glue (the Makefile's "./" references) ---
    cp -a "$PKGSRC/files/." "$D/$ZD/files/"                       # overlay repo files/*
    install -Dm755 "$PKGSRC/init.d.sh"      "$D/etc/init.d/zapret2"
    install -Dm755 "$PKGSRC/uci-def-cfg.sh" "$D/etc/uci-defaults/zapret2-uci-def-cfg.sh"
    for f in "$PKGSRC"/*.sh; do                                   # all mgmt scripts → /opt/zapret2/
        bn="$(basename "$f")"; [ "$bn" = "init.d.sh" ] && continue
        install -Dm755 "$f" "$D/$ZD/$bn"
    done
    install -Dm644 "$PKGSRC/config.default" "$D/$ZD/config"
    install -Dm644 "$PKGSRC/config.default" "$D/$ZD/config.default"
    # default ipset copies (non-conffile reference set)
    mkdir -p "$D/$ZD/ipset_def"
    for t in "$PKGSRC"/ipset/zapret*.txt; do install -Dm644 "$t" "$D/$ZD/ipset_def/$(basename "$t")"; done
    # --- conffiles: overlay repo source where present, else empty placeholder ---
    printf '%s\n' "$CONFFILES" | while read -r cf; do
        [ -z "$cf" ] && continue
        rel="${cf#/opt/zapret2/}"
        src="$PKGSRC/$rel"
        case "$rel" in */custom.d/*) src="$PKGSRC/custom.d/$(basename "$rel")";; esac
        [ "$rel" = "config" ] && continue   # already installed from config.default
        mkdir -p "$D$(dirname "$cf")"
        if [ -f "$src" ]; then install -m644 "$src" "$D$cf"; else : > "$D$cf"; fi
    done
    # --- permissions (mirror Makefile) ---
    chmod 644 "$D/$ZD"/ipset/*.txt 2>/dev/null || true
    chmod 644 "$D/$ZD"/ipset_def/*.txt 2>/dev/null || true
    chmod 644 "$D/$ZD"/init.d/openwrt/custom.d/*.sh 2>/dev/null || true
    chmod 644 "$D/$ZD"/config* 2>/dev/null || true
    chmod 755 "$D/$ZD"/*.sh 2>/dev/null || true
    chmod 755 "$D/$ZD"/nfq2/* "$D/$ZD"/ip2net/* "$D/$ZD"/mdig/* 2>/dev/null || true
}

for OW_ARCH in $OPENWRT_ARCHES; do
    echo "--- zapret2 $PKG_VERSION for $OW_ARCH ($BIN_SUBDIR) ---"
    BASE="$(mktemp -d)"; stage_base "$BASE"

    # ---- IPK ----
    IPK="$(mktemp -d)"; cp -a "$BASE/." "$IPK/"
    mkdir -p "$IPK/CONTROL"
    cat > "$IPK/CONTROL/control" <<EOF
Package: zapret2
Version: $PKG_VERSION
Architecture: $OW_ARCH
Depends: $PKG_DEPENDS
Section: net
Maintainer: bol-van
License: MIT
URL: https://github.com/bol-van/zapret2
Description: zapret2 (nfqws2) DPI bypass — prebuilt by 1andrevich/zapret2-openwrt
EOF
    printf '%s\n' "$CONFFILES" > "$IPK/CONTROL/conffiles"
    install -m755 "$CTRL/preinst"  "$IPK/CONTROL/preinst"
    install -m755 "$CTRL/postinst" "$IPK/CONTROL/postinst"
    install -m755 "$CTRL/prerm"    "$IPK/CONTROL/prerm"
    install -m755 "$CTRL/postrm"   "$IPK/CONTROL/postrm"
    fakeroot ipkg-build -m "" "$IPK" "$OUT_DIR"
    rm -rf "$IPK"

    # ---- APK ----
    APK="$(mktemp -d)"; cp -a "$BASE/." "$APK/"
    mkdir -p "$APK/lib/apk/packages"
    find "$APK" -type f,l -printf '/%P\n' | sort > "$APK/lib/apk/packages/zapret2.list"
    printf '%s\n' "$CONFFILES" > "$APK/lib/apk/packages/zapret2.conffiles"
    printf '%s\n' "$CONFFILES" | while read -r cf; do
        [ -z "$cf" ] && continue
        [ -f "$APK$cf" ] && sha256sum "$APK$cf" | sed "s,$APK/,,"
    done > "$APK/lib/apk/packages/zapret2.conffiles_static"
    apk mkpkg \
        --info "name:zapret2" \
        --info "version:$PKG_VERSION" \
        --info "description:zapret2 (nfqws2) DPI bypass" \
        --info "arch:$OW_ARCH" \
        --info "origin:zapret2" \
        --info "url:https://github.com/bol-van/zapret2" \
        --info "license:MIT" \
        --info "depends:$PKG_DEPENDS" \
        --script "pre-install:$CTRL/preinst" \
        --script "post-install:$CTRL/postinst" \
        --script "pre-upgrade:$CTRL/preinst" \
        --script "post-upgrade:$CTRL/postinst" \
        --script "pre-deinstall:$CTRL/prerm" \
        --script "post-deinstall:$CTRL/postrm" \
        ${APK_SIGN_KEY:+--sign-key "$APK_SIGN_KEY"} \
        --files "$APK" \
        --output "$OUT_DIR/zapret2_${PKG_VERSION}_${OW_ARCH}.apk"
    rm -rf "$APK" "$BASE"
    echo "Done: $OW_ARCH"
done
