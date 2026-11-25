# Costruisce Crocuta per Windows: l'app, uno zip portabile e l'installer.
#
# Il gemello di build_macos.sh e build_ipa.sh, da lanciare su un PC
# Windows con Flutter e i Build Tools di Visual Studio (C++):
#
#   powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1 [-WithEnv]
#
# Procura da se' quello che manca e che non richiede di installare niente
# a livello di sistema: nuget.exe (per il plugin della webview) e il
# modello voce/base. L'installer si fa con Inno Setup, se c'e'.
param([switch]$WithEnv)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutter = if ($env:FLUTTER) { $env:FLUTTER } else { "$env:USERPROFILE\development\flutter\bin\flutter.bat" }
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

# nuget.exe: il plugin flutter_inappwebview_windows lo chiama per
# scaricare WebView2 e le sue librerie, e senza la build si ferma.
$tools = "$env:LOCALAPPDATA\crocuta-tools"
New-Item -ItemType Directory -Force $tools | Out-Null
if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
  if (-not (Test-Path "$tools\nuget.exe")) {
    Write-Host '==> scarico nuget.exe'
    Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile "$tools\nuget.exe"
  }
  $env:PATH = "$tools;$env:PATH"
}

# Il modello voce/base di AutoMix, se manca.
& "$PSScriptRoot\fetch_models.ps1"

# La sincronizzazione si configura nelle Impostazioni dell'app: la build
# di serie non porta indirizzo ne' segreto e si puo' dare agli amici. Con
# -WithEnv il .env entra come valore iniziale, solo per i tuoi dispositivi.
$defines = @()
if ($WithEnv) {
  if (-not (Test-Path "$root\.env")) { throw '-WithEnv ma manca .env' }
  $defines = @('--dart-define-from-file=.env')
  Write-Host '==> uso .env: build SOLO per i tuoi dispositivi, non da condividere'
}

# I collegamenti ai plugin come junction: i link simbolici che crea Flutter
# su alcuni PC non si attraversano e CMake si ferma. Vedi
# fix_plugin_links.ps1.
& $flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'pub get fallito' }
& "$PSScriptRoot\fix_plugin_links.ps1" -Root $root

& $flutter build windows --release @defines
if ($LASTEXITCODE -ne 0) { throw 'build fallita' }

$app = "$root\build\windows\x64\runner\Release"

# libmpv con i filtri audio. Quello di media_kit per Windows ha il solo
# `equalizer`: con le bande di AutoMix (`bass`, `treble`) e con `aformat`
# per l'analisi e la separazione della voce la catena veniva rifiutata
# ("Audio filter initialized failed"). La build di shinchiro ha ffmpeg
# completo e la stessa interfaccia: si sostituisce la DLL, fissata a una
# versione e con l'impronta controllata. E' il gemello Windows del libmpv
# ricompilato di tool/build_libmpv.sh.
$mpvTag = '20260923'
$mpvArchive = 'mpv-dev-x86_64-20260923-git-6fd80b2003.7z'
$mpvSha = '372f29c292d0c8b4ce916225739e5872e35b8e11f3f4590c285baed8ba551100'
$mpvDir = "$tools\mpv-$mpvTag"
if (-not (Test-Path "$mpvDir\libmpv-2.dll")) {
  $archive = "$tools\$mpvArchive"
  if (-not (Test-Path $archive) -or (Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $mpvSha) {
    Write-Host '==> scarico libmpv con i filtri audio'
    Invoke-WebRequest "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/$mpvTag/$mpvArchive" -OutFile $archive
  }
  if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $mpvSha) {
    Remove-Item $archive
    throw "libmpv scaricato ma l'impronta non torna: rimosso"
  }
  New-Item -ItemType Directory -Force $mpvDir | Out-Null
  # Il tar di Windows (libarchive) legge anche i .7z.
  tar -xf $archive -C $mpvDir libmpv-2.dll
  if ($LASTEXITCODE -ne 0) { throw 'libmpv non estratto' }
}
Copy-Item -Force "$mpvDir\libmpv-2.dll" "$app\libmpv-2.dll"
Write-Host '==> libmpv con i filtri audio al posto di quello di media_kit' 
$version = (Select-String -Path "$root\pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$out = "$root\build\windows-dist"
New-Item -ItemType Directory -Force $out | Out-Null

# Lo zip portabile: si scompatta e si lancia Crocuta.exe.
$zip = "$out\Crocuta-$version-windows-portable.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$app\*" -DestinationPath $zip
Write-Host "OK: $zip"

# L'installer, con Inno Setup se c'e' (installazione per utente, senza
# permessi di amministratore).
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iscc) {
  & $iscc "/DAppVersion=$version" "/DSourceDir=$app" "/DOutDir=$out" "$PSScriptRoot\windows_installer.iss"
  if ($LASTEXITCODE -ne 0) { throw 'installer non creato' }
} else {
  Write-Host 'Inno Setup non trovato: solo lo zip. (winget install JRSoftware.InnoSetup)'
}
