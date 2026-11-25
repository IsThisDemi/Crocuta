#!/usr/bin/env bash
#
# Prepara un DMG di Crocuta per un altro Mac Apple Silicon: si apre, si
# trascina l'app in Applicazioni, fatto.
#
# Solo arm64: la build di Flutter e' universale, e la parte Intel si toglie
# nella copia per il DMG (ditto --arch arm64). Togliere un'architettura
# invalida la firma, quindi si rifirma tutto ad-hoc: prima le librerie,
# poi l'app con le sue autorizzazioni (sandbox e rete) — senza, l'app non
# potrebbe aprire il proxy dello streaming.
#
# Firma ad-hoc = nessun account sviluppatore a pagamento: al primo avvio
# macOS la blocca una volta, e il "Leggimi" nel DMG spiega come sbloccarla.
#
# Uso:  ./tool/build_dmg.sh            (ricompila e prepara il DMG)
#       ./tool/build_dmg.sh --no-build (usa l'app gia' compilata)
set -euo pipefail
cd "$(dirname "$0")/.."

[ "${1:-}" = "--no-build" ] || ./tool/build_macos.sh

SRC="build/macos/Build/Products/Release/Crocuta.app"
[ -d "$SRC" ] || { echo "manca $SRC: compila prima" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SRC/Contents/Info.plist")
OUT="build/dmg"
DMG="$OUT/Crocuta-$VERSION-apple-silicon.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Crocuta.app"

echo "==> copia solo arm64"
ditto --arch arm64 "$SRC" "$APP"

echo "==> rifirmo ad-hoc"
# Dall'interno verso l'esterno: una firma esterna vale solo se quelle
# interne sono gia' valide.
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' f; do codesign --force --sign - --timestamp=none "$f"; done
codesign --force --sign - --timestamp=none \
  --entitlements macos/Runner/Release.entitlements "$APP"
codesign --verify --deep --strict "$APP"

ln -s /Applications "$STAGE/Applicazioni"
cat > "$STAGE/Leggimi.txt" <<'TXT'
CROCUTA — installazione

1. Trascina Crocuta nella cartella Applicazioni qui accanto.
2. Apri Crocuta da Applicazioni.

Al primo avvio macOS dice che non puo' verificare lo sviluppatore (l'app
non passa dall'App Store e non e' notarizzata da Apple). Si sblocca una
volta sola, in uno di questi due modi:

  A) Impostazioni di Sistema > Privacy e sicurezza: in fondo compare
     "Crocuta e' stata bloccata": premi "Apri comunque" e conferma.

  B) Se invece dice che l'app "e' danneggiata", apri il Terminale e scrivi:
        xattr -dr com.apple.quarantine /Applications/Crocuta.app
     poi riapri Crocuta.

Serve un Mac Apple Silicon (M1 o successivo) con macOS 14 o piu' recente.
Il vetro "Liquid Glass" vero compare da macOS 26 in poi.
TXT

mkdir -p "$OUT"
rm -f "$DMG"
hdiutil create -volname "Crocuta" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✓ DMG pronto: $DMG ($(du -h "$DMG" | cut -f1))"
