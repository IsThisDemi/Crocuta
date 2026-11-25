# Collega i plugin di Flutter per Windows con delle junction.
#
# Flutter collega ogni plugin in windows\flutter\ephemeral\.plugin_symlinks
# con un link simbolico nella forma \\?\C:\...: su alcuni PC Windows non si
# attraversa ("File non trovato"), CMake non trova la cartella windows del
# plugin e la build si ferma — prima di sostituire libmpv, cosi' restava
# quello di media_kit senza i filtri di AutoMix. Una junction verso la
# stessa cartella si attraversa sempre.
#
# L'elenco dei plugin e le loro cartelle vengono da
# .flutter-plugins-dependencies, che scrive flutter pub get. Lo chiama
# build_windows.ps1, prima di flutter build.
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$deps = Join-Path $Root '.flutter-plugins-dependencies'
if (-not (Test-Path $deps)) { return }
$plugins = (Get-Content $deps -Raw | ConvertFrom-Json).plugins.windows
$dir = Join-Path $Root 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force $dir | Out-Null

$made = 0
foreach ($p in $plugins) {
  $link = Join-Path $dir $p.name
  $target = $p.path.TrimEnd('\', '/')
  # Gia' attraversabile: si lascia stare.
  if (Test-Path (Join-Path $link 'pubspec.yaml')) { continue }
  if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null }
  New-Item -ItemType Junction -Path $link -Target $target | Out-Null
  $made++
}
if ($made -gt 0) { Write-Host "==> $made plugin collegati con una junction" }
