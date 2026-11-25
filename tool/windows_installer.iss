; L'installer di Crocuta per Windows, con Inno Setup 6.
; Lo lancia tool\build_windows.ps1, che passa versione e cartelle:
;   ISCC /DAppVersion=0.1.0+1 /DSourceDir=... /DOutDir=... windows_installer.iss
;
; Installazione per utente, senza permessi di amministratore: e' un'app
; personale, e chiedere l'UAC per un lettore musicale sarebbe fuori luogo.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Un id fisso: e' cio' che fa riconoscere un aggiornamento come tale
; invece di installare una seconda copia accanto alla prima.
AppId={{8C3F5A2E-6B1D-4E9A-9F27-3D6C0B5E7A41}
AppName=Crocuta
AppVersion={#AppVersion}
AppPublisher=Crocuta
DefaultDirName={localappdata}\Programs\Crocuta
DefaultGroupName=Crocuta
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutDir}
OutputBaseFilename=Crocuta-{#AppVersion}-windows-setup
SetupIconFile={#SourceDir}\..\..\..\..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Crocuta.exe
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Crocuta"; Filename: "{app}\Crocuta.exe"
Name: "{autodesktop}\Crocuta"; Filename: "{app}\Crocuta.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Crocuta.exe"; Description: "{cm:LaunchProgram,Crocuta}"; Flags: nowait postinstall skipifsilent
