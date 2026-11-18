#!/usr/bin/env bash
set -euo pipefail

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export DEVKITA64="${DEVKITA64:-$DEVKITPRO/devkitA64}"

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

if [[ ! -f "$DEVKITPRO/libounce/switch2_rules" ]]; then
  echo "ERROR: switch2_rules not found at $DEVKITPRO/libounce/switch2_rules" >&2
  exit 1
fi

PREFIX_LOCAL="${PREFIX_LOCAL:-$ROOT_DIR/prefix-switch2}"
BUILD_DIR="$ROOT_DIR/build-switch2"
FFMPEG_VER="7.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz"
FFMPEG_SHA256="40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6"
FFMPEG_PATCH_BASE="https://raw.githubusercontent.com/devkitPro/pacman-packages/e09c9f0d0f3e19e25bc75f78481959b658df6d4d/switch/ffmpeg"
FFMPEG_PATCH_FALLBACK="https://raw.githubusercontent.com/devkitPro/pacman-packages/master/switch/ffmpeg"
FFMPEG_PATCH_SHA256="1792380b992e3554a4abcddf0d7b395bfd8c118ac7c6e38c8f2fb0d39753a390"
TLS_PATCH_SHA256="57ea7ec8ed26d13d3172d0fd589b7883d22f0c180d50b7434fcc73fb2b3ab7d7"

FFMPEG_WORK="$BUILD_DIR/ffmpeg-src"
FFMPEG_BUILD="$BUILD_DIR/ffmpeg-build"
FFMPEG_PREFIX="$BUILD_DIR/ffmpeg-install"
JOBS="${NETSURF_SWITCH2_JOBS:-$(nproc)}"

fetch_verified() {
  local url="$1"
  local fallback="$2"
  local dest="$3"
  local expected_sha="$4"
  if [[ -f "$dest" ]] && echo "${expected_sha}  ${dest}" | sha256sum -c - >/dev/null 2>&1; then
    return 0
  fi
  rm -f "$dest"
  if ! curl -fsSL -o "$dest" "$url"; then
    if [[ -n "$fallback" ]]; then
      curl -fsSL -o "$dest" "$fallback"
    else
      return 1
    fi
  fi
  echo "${expected_sha}  ${dest}" | sha256sum -c -
}

echo "==> Ensuring Switch 2 local prefix (libiconv + QuickJS-ng)..."
bash "$ROOT_DIR/tools-switch/build-prefix-switch2.sh" "$PREFIX_LOCAL"

if [[ ! -f "$FFMPEG_PREFIX/lib/libavcodec.a" ]] || [[ ! -f "$FFMPEG_PREFIX/lib/libavutil.a" ]] || [[ ! -f "$FFMPEG_PREFIX/lib/libavformat.a" ]]; then
  echo "==> Building clean Switch 2 FFmpeg ${FFMPEG_VER} (--disable-nvtegra)..."
  rm -rf "$FFMPEG_WORK" "$FFMPEG_BUILD"
  mkdir -p "$FFMPEG_WORK" "$FFMPEG_BUILD" "$FFMPEG_PREFIX"

  fetch_verified "$FFMPEG_URL" "" "$FFMPEG_WORK/ffmpeg-${FFMPEG_VER}.tar.xz" "$FFMPEG_SHA256"
  fetch_verified "${FFMPEG_PATCH_BASE}/ffmpeg-${FFMPEG_VER}.patch" "${FFMPEG_PATCH_FALLBACK}/ffmpeg-${FFMPEG_VER}.patch" "$FFMPEG_WORK/ffmpeg-${FFMPEG_VER}.patch" "$FFMPEG_PATCH_SHA256"
  fetch_verified "${FFMPEG_PATCH_BASE}/tls.patch" "${FFMPEG_PATCH_FALLBACK}/tls.patch" "$FFMPEG_WORK/tls.patch" "$TLS_PATCH_SHA256"

  tar -xJf "$FFMPEG_WORK/ffmpeg-${FFMPEG_VER}.tar.xz" -C "$FFMPEG_WORK"
  FFMPEG_SRC="$FFMPEG_WORK/ffmpeg-${FFMPEG_VER}"
  patch -d "$FFMPEG_SRC" -Np1 -i "$FFMPEG_WORK/ffmpeg-${FFMPEG_VER}.patch"
  patch -d "$FFMPEG_SRC" -Np1 -i "$FFMPEG_WORK/tls.patch"
  chmod +x "$FFMPEG_SRC/configure"
  find "$FFMPEG_SRC" -name '*.sh' -exec chmod +x {} +

  (
    cd "$FFMPEG_BUILD"
    export PATH="$DEVKITPRO/tools/bin:$DEVKITA64/bin:$DEVKITPRO/portlibs/switch2/bin:$DEVKITPRO/portlibs/switch/bin:$PATH"
    export PKG_CONFIG_PATH="$DEVKITPRO/portlibs/switch2/lib/pkgconfig:$DEVKITPRO/portlibs/switch/lib/pkgconfig"
    bash "$FFMPEG_SRC/configure" \
      --prefix="$FFMPEG_PREFIX" \
      --enable-gpl \
      --disable-shared \
      --enable-static \
      --cross-prefix=aarch64-none-elf- \
      --enable-cross-compile \
      --arch=aarch64 \
      --cpu=cortex-a78c \
      --target-os=horizon \
      --enable-pic \
      --extra-cflags="-D__SWITCH__ -D__SWITCH2__ -D_GNU_SOURCE -O2 -mcpu=cortex-a78c+crypto -mtp=soft -fPIC -ftls-model=local-exec -I${DEVKITPRO}/libounce/include -I${DEVKITPRO}/portlibs/switch2/include -I${DEVKITPRO}/portlibs/switch/include" \
      --extra-cxxflags="-D__SWITCH__ -D__SWITCH2__ -D_GNU_SOURCE -O2 -mcpu=cortex-a78c+crypto -mtp=soft -fPIC -ftls-model=local-exec -I${DEVKITPRO}/libounce/include -I${DEVKITPRO}/portlibs/switch2/include -I${DEVKITPRO}/portlibs/switch/include" \
      --extra-ldflags="-fPIE -L${DEVKITPRO}/portlibs/switch2/lib -L${DEVKITPRO}/portlibs/switch/lib -L${DEVKITPRO}/libounce/lib" \
      --disable-runtime-cpudetect \
      --disable-programs \
      --disable-debug \
      --disable-doc \
      --disable-autodetect \
      --enable-asm \
      --enable-neon \
      --disable-avdevice \
      --disable-encoders \
      --disable-muxers \
      --disable-avfilter \
      --enable-swscale \
      --enable-swresample \
      --enable-network \
      --disable-protocols \
      --enable-protocol=file,http,https,ftp,tcp,udp,rtmp,rtmpt,hls,crypto,tls,httpproxy \
      --enable-zlib \
      --enable-bzlib \
      --enable-libdav1d \
      --enable-libnx \
      --disable-nvtegra
    make -j"$JOBS"
    make install
  )
  rm -rf "$FFMPEG_WORK" "$FFMPEG_BUILD"
fi

echo "==> Building NetSurf for Nintendo Switch 2 (libounce + OunceVK)..."
export PATH="$DEVKITPRO/portlibs/switch2/bin:$DEVKITPRO/portlibs/switch/bin:$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"
ARCH_FLAGS="-march=armv8-a+crc+crypto+lse -mcpu=cortex-a78c+crypto -mtp=soft -fPIC -ftls-model=local-exec"
CPPFLAGS="-D__SWITCH__ -D__SWITCH2__ -I${FFMPEG_PREFIX}/include -I${PREFIX_LOCAL}/include -I${DEVKITPRO}/portlibs/switch2/include -I${DEVKITPRO}/portlibs/switch/include -I${DEVKITPRO}/libounce/include"
export CFLAGS="$CPPFLAGS $ARCH_FLAGS -O2 -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$ARCH_FLAGS -L${FFMPEG_PREFIX}/lib -L${PREFIX_LOCAL}/lib -L${DEVKITPRO}/portlibs/switch2/lib -L${DEVKITPRO}/portlibs/switch/lib -L${DEVKITPRO}/libounce/lib"
export PKG_CONFIG_LIBDIR="$ROOT_DIR/inst-framebuffer/lib/pkgconfig:${FFMPEG_PREFIX}/lib/pkgconfig:${PREFIX_LOCAL}/lib/pkgconfig:${DEVKITPRO}/portlibs/switch2/lib/pkgconfig:${DEVKITPRO}/portlibs/switch/lib/pkgconfig"
unset PKG_CONFIG_PATH

rm -f "$ROOT_DIR/inst-framebuffer/build-stamp" "$ROOT_DIR/netsurf/nsfb" "$ROOT_DIR/netsurf/nsfb-switch2.map"
make HOST=aarch64-none-elf TARGET=framebuffer SWITCH2=1 SWITCH2_FFMPEG_DIR="$FFMPEG_PREFIX" -j"$JOBS"

echo "==> Packaging netsurf-switch2.nro..."
cd "$ROOT_DIR/netsurf"
DIST="switch-dist"
aarch64-none-elf-strip -o "$DIST/nsfb-stripped" nsfb
for f in default.css internal.css quirks.css adblock.css welcome.html; do
  [ -f "frontends/framebuffer/res/$f" ] && cp -L "frontends/framebuffer/res/$f" "$DIST/romfs/res/" || true
done
[ -f resources/default.css ] && cp resources/default.css "$DIST/romfs/res/default.css"
"$DEVKITPRO/tools/bin/nacptool" --create "NetSurf (Switch 2)" "etonedemid / David Kalil Braga" "3.12" "$DIST/netsurf.nacp"
"$DEVKITPRO/tools/bin/elf2nro" "$DIST/nsfb-stripped" "$DIST/netsurf.nro" \
  --icon="$DIST/netsurf-icon.jpg" --nacp="$DIST/netsurf.nacp" --romfsdir="$DIST/romfs"

cp -f "$DIST/netsurf.nro" "$ROOT_DIR/netsurf.nro"
cp -f "$DIST/netsurf.nro" "$ROOT_DIR/netsurf-switch2.nro"

python3 "$ROOT_DIR/tools/verify_switch2_package.py" \
  "$ROOT_DIR/netsurf-switch2.nro" \
  --link-map "$ROOT_DIR/netsurf/nsfb-switch2.map"

printf '\nBuilt: %s\n' "$ROOT_DIR/netsurf-switch2.nro"
