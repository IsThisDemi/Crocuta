#!/usr/bin/env bash
#
# Costruisce l'app macOS in release, firmata ad-hoc.
#
# Uso:  ./tool/build_macos.sh [--debug] [--with-env]
#
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
command -v "$FLUTTER" >/dev/null 2>&1 || FLUTTER="flutter"

MODE="--release"
WITH_ENV=0
for arg in "$@"; do
  case "$arg" in
    --debug) MODE="--debug" ;;
    --with-env) WITH_ENV=1 ;;
    *) echo "opzione sconosciuta: $arg" >&2; exit 1 ;;
  esac
done

# Indirizzo e segreto della sincronizzazione si scrivono nelle Impostazioni
# dell'app, su ogni dispositivo: la build di serie non ne porta, e si puo'
# dare agli amici. Con --with-env il .env entra nella build come valore
# iniziale, adottato e salvato al primo avvio — solo per i tuoi dispositivi.
ENV_FLAG=()
if [ "$WITH_ENV" = 1 ]; then
  [ -f .env ] || { echo "--with-env ma manca .env" >&2; exit 1; }
  ENV_FLAG=(--dart-define-from-file=.env)
  echo "==> uso .env: build SOLO per i tuoi dispositivi, non da condividere"
fi

# Il modello voce/base di AutoMix, se manca.
./tool/fetch_models.sh

"$FLUTTER" build macos "$MODE" "${ENV_FLAG[@]}"

# Rifirma ad-hoc, dall'interno verso l'esterno. La firma che esce da
# Xcode non regge: App.framework viene toccato dopo essere stato firmato,
# e la verifica stretta boccia l'app intera ("nested code is modified").
# Una firma esterna vale solo se quelle interne sono gia' valide.
if [ "$MODE" = "--release" ]; then
  APP="build/macos/Build/Products/Release/Crocuta.app"
  echo "==> rifirmo ad-hoc"
  find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 |
    while IFS= read -r -d '' f; do codesign --force --sign - --timestamp=none "$f"; done
  # Il widget, con la sua sandbox e l'eccezione per leggere il brano in
  # corso: un'estensione senza sandbox macOS non la carica.
  for ext in "$APP/Contents/PlugIns/"*.appex; do
    [ -e "$ext" ] || continue
    codesign --force --sign - --timestamp=none \
      --entitlements macos/CrocutaWidget/CrocutaWidget.entitlements "$ext"
  done
  codesign --force --sign - --timestamp=none \
    --entitlements macos/Runner/Release.entitlements "$APP"
  codesign --verify --deep --strict "$APP"
  echo "==> firma valida"
fi
