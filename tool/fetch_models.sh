#!/bin/bash
# Scarica i modelli di AutoMix: quello che separa voce e base e quello
# che trova i battiti.
#
# Stanno fuori da git e si scaricano una volta, con l'impronta
# controllata: un modello troncato o diverso darebbe risultati sbagliati
# senza nessun errore.
#
# Uso: ./tool/fetch_models.sh   (lo chiamano gia' gli script di build)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# fetch <destinazione> <url> <sha256> <descrizione>
fetch() {
  local dest="$1" url="$2" sha="$3" what="$4"
  check() { [ -f "$dest" ] && [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$sha" ]; }
  if check; then return; fi
  mkdir -p "$(dirname "$dest")"
  echo "==> scarico $what"
  curl -fL --retry 3 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
  if ! check; then
    rm -f "$dest"
    echo "$what scaricato ma l'impronta non torna: rimosso" >&2
    exit 1
  fi
  echo "✓ $what in $dest"
}

fetch "$ROOT/assets/models/voc_ft.onnx" \
  "https://github.com/TRvlvr/model_repo/releases/download/all_public_uvr_models/UVR-MDX-NET-Voc_FT.onnx" \
  534b2070fcc7df514b13ef660dc8cbb328679c2374d04354a5c42bb14ecce111 \
  "il modello voce/base (64 MB)"

# Beat This! (CPJKU, ISMIR 2024, licenza MIT): battiti e primi tempi di
# battuta. Il checkpoint "final0" convertito in ONNX; verificato contro
# l'originale PyTorch, stessi valori a 3e-6. 82 MB.
fetch "$ROOT/assets/models/beat_this.onnx" \
  "https://github.com/CattyCathy/beat-this-onnx/releases/download/v0.0.1/beat-this-final0.onnx" \
  e5e37b7d1802895e42559c5a1ced7619b1601d257a5c8e167c9d45de37c1b078 \
  "il modello dei battiti (82 MB)"

# ONNX Runtime 1.30 per il Mac, al posto della 1.15 del pacchetto Dart.
#
# Con la 1.30 CoreML esegue il modello sulla GPU: sul Mac M5 Pro 30 s di
# audio si separano in 2,1 s invece di 9,9, con la stessa identica voce
# (53,6 dB contro il riferimento Python in entrambi i casi). La 1.15
# accettava CoreML ma ricadeva sulla CPU. 42 MB: fuori da git, come il
# modello, e con l'impronta controllata.
ORT_DEST="$ROOT/third_party/onnxruntime/macos/libonnxruntime.1.30.0.dylib"
ORT_URL="https://github.com/microsoft/onnxruntime/releases/download/v1.30.0/onnxruntime-osx-arm64-1.30.0.tgz"
ORT_TGZ_SHA="6ebb5062a934537c352937821f9fe9718e7de1a2db1122a93dd363ffd53a7012"
ORT_SHA="bcc9110f9d638a119de2db7afb3ba9a1da8085f0cb3401e1c48ae1caf450b6fa"

# La libreria si presenta come @rpath/libonnxruntime.1.dylib, ma nel
# pacchetto si chiama col numero intero: l'app, collegata a lei, all'avvio
# cercava il nome breve, non lo trovava e non partiva. Le si da' il nome
# con cui sta nel pacchetto, e una firma nuova, perche' cambiarlo invalida
# quella di Microsoft. Il segno che e' gia' fatto e' il nome stesso.
ORT_ID="@rpath/libonnxruntime.1.30.0.dylib"
ort_ok() { [ -f "$ORT_DEST" ] && [ "$(otool -D "$ORT_DEST" | tail -1)" = "$ORT_ID" ]; }

if ! ort_ok; then
  echo "==> scarico ONNX Runtime 1.30 per il Mac"
  TMP=$(mktemp -d)
  curl -fL --retry 3 -o "$TMP/ort.tgz" "$ORT_URL"
  if [ "$(shasum -a 256 "$TMP/ort.tgz" | cut -d' ' -f1)" != "$ORT_TGZ_SHA" ]; then
    rm -rf "$TMP"
    echo "ONNX Runtime scaricato ma l'impronta non torna" >&2
    exit 1
  fi
  tar xzf "$TMP/ort.tgz" -C "$TMP"
  LIB="$TMP/onnxruntime-osx-arm64-1.30.0/lib/libonnxruntime.1.30.0.dylib"
  if [ "$(shasum -a 256 "$LIB" | cut -d' ' -f1)" != "$ORT_SHA" ]; then
    rm -rf "$TMP"
    echo "libreria ONNX Runtime diversa da quella attesa" >&2
    exit 1
  fi
  cp "$LIB" "$ORT_DEST"
  install_name_tool -id "$ORT_ID" "$ORT_DEST" 2>/dev/null
  codesign --force --sign - --timestamp=none "$ORT_DEST"
  rm -rf "$TMP"
  ort_ok || { echo "libreria ONNX Runtime non valida" >&2; exit 1; }
  echo "✓ ONNX Runtime in $ORT_DEST"
fi
