; Inno Setup script for Nabira (Windows).
; Packages the self-contained single-file exe into a per-user installer with a Start-Menu
; shortcut and an uninstaller. Autostart is handled by the app itself (Settings → "Launch at
; startup"), so the installer does not add a Run key. Compiled by the windows-release CI (ISCC).
;
; Expected defines (passed by CI with /D...):
;   MyAppVersion  — e.g. 0.9.0
;   SourceExe     — path to the published Nabira.exe
; Falls back to sensible defaults for a local compile.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceExe
  #define SourceExe "..\src\Nabira.Win\bin\Release\net8.0-windows\win-x64\publish\Nabira.exe"
#endif

#define MyAppName "Nabira"
#define MyAppPublisher "Nabira"
#define MyAppURL "https://nabira.site"
#define MyAppExeName "Nabira.exe"

[Setup]
; A stable AppId ties upgrades/uninstalls together across versions — never change it.
AppId={{A3F5C1E2-7B94-4D6A-9E31-2C8F5A1B6D40}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; Per-user install → no UAC elevation needed (matches a menu-bar utility's footprint).
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=Nabira-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
