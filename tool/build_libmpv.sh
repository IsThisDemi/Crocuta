#!/bin/bash
# Ricompila libmpv per macOS e iOS con i filtri audio di ffmpeg.
#
# Il libmpv che media_kit scarica ha di ffmpeg il solo filtro `equalizer`:
# volume, highpass, ebur128, alimiter, atempo... mancano, e con uno di loro
# nella catena il brano non suona ("Audio filter initialized failed").
# AutoMix li usa tutti, quindi le librerie si ricompilano da
# media-kit/libmpv-darwin-build alla stessa versione che usa media_kit
# (v0.6.0), aggiungendo solo i filtri — e le correzioni per compilare con
# Xcode 26, cmake 4 e meson 1.12, strumenti che nel 2023 non esistevano.
# Tutto sta in tool/libmpv/yeen-filters.patch.
#
# Uso: ./tool/build_libmpv.sh [macos|ios|all]   (default: all)
# Serve: brew install cmake go meson ninja
#
# Ci vuole una ventina di minuti per piattaforma. Alla fine i framework
# finiscono in third_party/media_kit_libs_{macos,ios}_video, che il
# pubspec usa al posto dei pacchetti pubblicati.
set -euo pipefail

TARGET="${1:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# La cartella di lavoro: i cross-file della patch ricevono il suo percorso
# assoluto subito dopo il git apply.
WORK="${LIBMPV_WORK:-$HOME/Docs/libmpv-build/libmpv-darwin-build}"
VERSION=v0.6.0-yeen

if [ ! -d "$WORK" ]; then
  mkdir -p "$(dirname "$WORK")"
  git clone https://github.com/media-kit/libmpv-darwin-build.git "$WORK"
fi
cd "$WORK"
if [ -z "$(git status --porcelain)" ]; then
  git fetch --depth 1 origin tag v0.6.0
  git checkout -q v0.6.0
  git apply "$ROOT/tool/libmpv/yeen-filters.patch"
  # La patch lascia @WORK@ dove i cross-file vogliono il percorso assoluto
  # di compat/sincosf.h: lo si mette qui, per la macchina che compila.
  sed -i '' "s|@WORK@|$WORK|g" cross-files/*.ini
fi

install_frameworks() { # <os> <pacchetto>
  local archive="build/output/libmpv-xcframeworks_${VERSION}_$1-universal-video-default.tar.gz"
  make VERSION="$VERSION" "$archive"
  local dest="$ROOT/third_party/$2/$1/Frameworks"
  local tmp
  tmp="$(mktemp -d)"
  tar -xzf "$archive" -C "$tmp"
  rm -rf "$dest"/*.xcframework "$dest/.symlinks"
  cp -R "$tmp"/*/*.xcframework "$dest/"
  rm -rf "$tmp"
  make -C "$ROOT/third_party/$2/$1"
  echo "✓ $1: framework in $dest"
}

case "$TARGET" in
  macos) install_frameworks macos media_kit_libs_macos_video ;;
  ios) install_frameworks ios media_kit_libs_ios_video ;;
  all)
    install_frameworks macos media_kit_libs_macos_video
    install_frameworks ios media_kit_libs_ios_video
    ;;
  *) echo "uso: $0 [macos|ios|all]" >&2; exit 1 ;;
esac
