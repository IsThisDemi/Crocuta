# Scarica i modelli di AutoMix (voce/base e battiti), su Windows.
# Gemello di tool/fetch_models.sh: stesso file, stessa impronta.
#
# Uso (da PowerShell, nella cartella del progetto):
#   powershell -ExecutionPolicy Bypass -File tool\fetch_models.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Get-Model($dest, $url, $sha, $what) {
  $ok = { (Test-Path $dest) -and ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $sha) }
  if (& $ok) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Write-Host "==> scarico $what"
  Invoke-WebRequest -Uri $url -OutFile "$dest.part"
  Move-Item -Force "$dest.part" $dest
  if (-not (& $ok)) {
    Remove-Item $dest
    throw "$what scaricato ma l'impronta non torna: rimosso"
  }
  Write-Host "OK: $what in $dest"
}

Get-Model (Join-Path $root 'assets\models\voc_ft.onnx') `
  'https://github.com/TRvlvr/model_repo/releases/download/all_public_uvr_models/UVR-MDX-NET-Voc_FT.onnx' `
  '534b2070fcc7df514b13ef660dc8cbb328679c2374d04354a5c42bb14ecce111' `
  'il modello voce/base (64 MB)'

# Beat This! (CPJKU, licenza MIT): battiti e primi tempi di battuta.
Get-Model (Join-Path $root 'assets\models\beat_this.onnx') `
  'https://github.com/CattyCathy/beat-this-onnx/releases/download/v0.0.1/beat-this-final0.onnx' `
  'e5e37b7d1802895e42559c5a1ced7619b1601d257a5c8e167c9d45de37c1b078' `
  'il modello dei battiti (82 MB)'
