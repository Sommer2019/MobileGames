; Inno Setup script for the Windows installer (built in CI, see
; .github/workflows/build.yml). Installs per user, no admin rights needed.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputName
  #define OutputName "MobileGames-Windows-Setup"
#endif

[Setup]
AppId={{6F1D6C2E-3B8A-4D55-9C1E-2A7F0E4B9D13}
AppName=Mobile Games
AppVersion={#AppVersion}
AppPublisher=Sommer2019
AppPublisherURL=https://github.com/Sommer2019/MobileGames
DefaultDirName={localappdata}\Programs\Mobile Games
DefaultGroupName=Mobile Games
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename={#OutputName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mobile_games.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Mobile Games"; Filename: "{app}\mobile_games.exe"
Name: "{autodesktop}\Mobile Games"; Filename: "{app}\mobile_games.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mobile_games.exe"; Description: "{cm:LaunchProgram,Mobile Games}"; Flags: nowait postinstall skipifsilent
