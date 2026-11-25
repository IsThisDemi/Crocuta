#!/usr/bin/env bash
#
# Costruisce un .ipa NON firmato, pronto per AltStore.
#
# AltStore ri-firma l'app con il TUO Apple ID gratuito al momento
# dell'installazione, quindi qui non serve — e non si deve usare —
# nessun team di sviluppo a pagamento.
#
# Uso:  ./tool/build_ipa.sh [--with-env]
#
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
command -v "$FLUTTER" >/dev/null 2>&1 || FLUTTER="flutter"

WITH_ENV=0
for arg in "$@"; do
  case "$arg" in
    --with-env) WITH_ENV=1 ;;
    *) echo "opzione sconosciuta: $arg" >&2; exit 1 ;;
  esac
done

APP="build/ios/iphoneos/Runner.app"
OUT_DIR="build/ipa"
IPA_NAME="Crocuta.ipa"

echo "==> flutter pub get"
"$FLUTTER" pub get

echo "==> Build iOS release (senza firma)"
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

"$FLUTTER" build ios --release --no-codesign "${ENV_FLAG[@]}"

if [ ! -d "$APP" ]; then
  echo "ERRORE: $APP non trovato. La build è fallita?" >&2
  exit 1
fi

echo "==> Impacchetto in Payload/"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Payload"
cp -R "$APP" "$OUT_DIR/Payload/Runner.app"

# Firme residue di una eventuale build Xcode precedente: AltStore firma
# da zero e una firma vecchia può confondere il re-signer.
rm -rf "$OUT_DIR/Payload/Runner.app/_CodeSignature"
rm -f  "$OUT_DIR/Payload/Runner.app/embedded.mobileprovision"

# Firma ad-hoc di framework e app shell.
#
# Sembra superfluo, visto che AltStore rifirma tutto col tuo Apple ID. Non
# lo e': ldid, che AltSign usa per rifirmare, si rifiuta di leggere i
# framework Flutter del tutto PRIVI di firma e aborta con
#
#   ldid.cpp: _assert(): end >= size - 0x10        (AltSign.Error 0)
#
# Qui 22 framework su 25 arrivano non firmati, perche' la build usa
# --no-codesign. Una firma ad-hoc ("-") da' a ldid una struttura valida da
# leggere, che poi sovrascrive con quella vera.
echo "==> Firma ad-hoc di framework e app (serve a ldid)"
for fw in "$OUT_DIR/Payload/Runner.app/Frameworks/"*; do
  [ -e "$fw" ] || continue
  codesign --force --sign - "$fw" >/dev/null 2>&1 || echo "   ! firma fallita: $(basename "$fw")"
done
# Il widget e l'app con le loro autorizzazioni: AltStore legge da qui quali
# capacita' registrare col tuo Apple ID, e senza l'App Group il widget non
# vedrebbe mai il brano in corso. Prima il widget, che sta dentro l'app:
# una firma esterna vale solo se quelle interne sono gia' valide.
APP_PLIST="$OUT_DIR/Payload/Runner.app/Info.plist"
for ext in "$OUT_DIR/Payload/Runner.app/PlugIns/"*.appex; do
  [ -e "$ext" ] || continue
  rm -rf "$ext/_CodeSignature" "$ext/embedded.mobileprovision"
  # La versione dell'app anche nel widget. Flutter la definisce solo per
  # l'app: nel widget restava vuota, e iOS rifiutava l'installazione
  # ("bundleVersion must be set ... for an app extension"). Devono anche
  # coincidere, o iOS rifiuta l'estensione.
  for key in CFBundleShortVersionString CFBundleVersion; do
    value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_PLIST")
    /usr/libexec/PlistBuddy -c "Delete :$key" "$ext/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$ext/Info.plist"
  done
  codesign --force --sign - --entitlements ios/CrocutaWidget/CrocutaWidget.entitlements \
    "$ext" >/dev/null 2>&1 || echo "   ! firma fallita: $(basename "$ext")"
done
codesign --force --sign - --entitlements ios/Runner/Runner.entitlements \
  "$OUT_DIR/Payload/Runner.app" >/dev/null 2>&1 ||
  echo "   ! firma ad-hoc dell'app fallita"

echo "==> Creo l'IPA"
# Lo zip va fatto DA DENTRO $OUT_DIR: la radice dell'archivio deve essere
# "Payload/", non "build/ipa/Payload/", altrimenti AltStore lo rifiuta
# in silenzio. È l'errore di packaging più comune.
( cd "$OUT_DIR" && zip -qry "$IPA_NAME" Payload )
rm -rf "$OUT_DIR/Payload"

SIZE=$(du -h "$OUT_DIR/$IPA_NAME" | cut -f1)

echo
echo "✅ IPA pronto: $(pwd)/$OUT_DIR/$IPA_NAME  ($SIZE)"
echo
echo "   Per installarlo:"
echo "   • trascinalo sull'icona di AltServer nella barra dei menu, oppure"
echo "   • apri AltStore sull'iPhone (stessa Wi-Fi del Mac) e tocca + in alto a sinistra."
echo
