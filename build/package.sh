#!/usr/bin/env bash
# Assemble one ZeroTierForKSU module zip from a repo checkout + prebuilt artifacts.
#
# Required env:
#   ARCH            arm64 | arm
#   TOOLCHAIN       GCC | NDK
#   SSO             0 | 1            (SSO is only built for arm64)
#   ZT_VERSION      e.g. 1.16.2
#   MODULE_VERSION  e.g. 10560
#   BINARY_PATH     path to the built zerotier-one
#   WEBROOT_PATH    path to the built UI (webroot dir)
#   CURL_PATH       path to the static curl binary for this arch
# Optional env:
#   LIB_PATH        path to a dir with libc++_shared.so (NDK builds)
#   UPDATE_JSON     module.prop updateJson value
#                    (default: raw githubusercontent main branch json for this variant)
#   OUT             output zip name (default: ZeroTierForKSU-<toolchain>[-SSO]-<arch>-<ver>.zip)
#   REPO_ROOT       repo checkout to package (default: $GITHUB_WORKSPACE or script/../..)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# package.sh lives in <repo>/build, repo root is one level up (override with REPO_ROOT)
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

: "${ARCH:?ARCH is required}"
: "${TOOLCHAIN:?TOOLCHAIN is required}"
: "${SSO:?SSO is required}"
: "${ZT_VERSION:?ZT_VERSION is required}"
: "${MODULE_VERSION:?MODULE_VERSION is required}"
: "${BINARY_PATH:?BINARY_PATH is required}"
: "${WEBROOT_PATH:?WEBROOT_PATH is required}"
: "${CURL_PATH:?CURL_PATH is required}"

SSO_SUFFIX=""
if [ "$SSO" = "1" ]; then
  SSO_SUFFIX="-SSO"
fi
if [ -z "${OUT:-}" ]; then
  OUT="ZeroTierForKSU-${TOOLCHAIN}${SSO_SUFFIX}-${ARCH}-${MODULE_VERSION}.zip"
fi
# updater manifest (json committed to the repo by the release workflow):
#   GCC arm64       -> update_arm64.json        GCC arm64-sso -> update_arm64-sso.json
#   GCC arm         -> update_arm.json          NDK arm64     -> update_arm64-ndk.json
#   NDK arm         -> update_arm-ndk.json      NDK arm64-sso -> update_arm64-ndk-sso.json
# dev packages append "_dev" (DEV_SUFFIX=_dev): update_arm64_dev.json etc.
if [ -z "${UPDATE_JSON:-}" ]; then
  VARIANT_SUFFIX=""
  [ "$TOOLCHAIN" = "NDK" ] && VARIANT_SUFFIX="-ndk"
  SSO_JSON_SUFFIX=""
  [ "$SSO" = "1" ] && SSO_JSON_SUFFIX="-sso"
  UPDATE_BRANCH="${UPDATE_BRANCH:-main}"
  UPDATE_JSON="https://raw.githubusercontent.com/BROBIRD/ZeroTierForKSU/${UPDATE_BRANCH}/update_${ARCH}${VARIANT_SUFFIX}${SSO_JSON_SUFFIX}${DEV_SUFFIX:-}.json"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# copy module files (everything whitelisted in module_file)
# strip CR so a CRLF checkout (core.autocrlf=true on Windows) packages identically to CI
mkdir -p "$STAGE/module"
(
  cd "$REPO_ROOT"
  while read -r entry; do
    [ -z "$entry" ] && continue
    if [ -e "$entry" ]; then
      cp -r "$entry" "$STAGE/module/"
    fi
  done < <(tr -d '\r' < module_file)
)

# build.sh/module_file drive the zip step from inside the staging dir
# (build.sh zips its own directory; both are excluded from the zip by build.sh itself)
tr -d '\r' < "$REPO_ROOT/build.sh" > "$STAGE/module/build.sh"
tr -d '\r' < "$REPO_ROOT/module_file" > "$STAGE/module/module_file"

cd "$STAGE/module"

# binaries and UI
cp "$BINARY_PATH" zerotier-one
chmod 755 zerotier-one zerotier-cli zerotier-idtool zerotier.sh api.sh service.sh customize.sh action.sh uninstall.sh build.inotify zerotier.inotify 2>/dev/null || true

rm -rf webroot
mkdir -p webroot
cp -r "$WEBROOT_PATH"/. webroot/

# static curl + cacert
mkdir -p bin
cp "$CURL_PATH" bin/curl
chmod 755 bin/curl
if [ ! -f bin/cacert.pem ]; then
  wget -qO bin/cacert.pem https://curl.se/ca/cacert.pem
fi

# NDK shared library
rm -rf lib
if [ -n "${LIB_PATH:-}" ] && [ -d "$LIB_PATH" ]; then
  cp -r "$LIB_PATH" lib
fi

# module.prop
cat > module.prop <<EOF
id=ZeroTierForKSU
name=ZeroTier For KernelSU
version=${ZT_VERSION}(${MODULE_VERSION})
versionCode=${MODULE_VERSION}
author=BROBIRD
description=ZeroTier(${ZT_VERSION}) with UI interface (${TOOLCHAIN}${SSO_SUFFIX}) build
updateJson=${UPDATE_JSON}
arch=${ARCH}
EOF

# zip it (reuse upstream build.sh which honors the module_file whitelist)
bash build.sh "$OUT"
unzip -l "$OUT"

# publish artifact next to the workspace
DEST_DIR="${PACKAGE_OUT_DIR:-$REPO_ROOT}"
mv -f "$OUT" "$DEST_DIR/$OUT"
echo "packaged: $DEST_DIR/$OUT"
