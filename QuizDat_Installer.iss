; QuizDat Installer Script - Inno Setup
; Generated for QuizDat v1.0.0

#define MyAppName "QuizDat"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "QuizDat"
#define MyAppExeName "QuizDat.exe"
#define MyAppIcon "Front-end\QuizDat\windows\runner\resources\app_icon.ico"
#define MyAppSourceDir "Front-end\QuizDat\build\windows\x64\runner\Release"

[Setup]
AppId={{B4F2A1C3-9D8E-4F7A-B3C2-1A2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=.
OutputBaseFilename=QuizDat_Setup
SetupIconFile={#MyAppIcon}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Tạo shortcut trên Desktop"; GroupDescription: "Shortcut:"

[Files]
; Toàn bộ thư mục Release được đóng gói
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Shortcut trong Start Menu
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Gỡ cài đặt {#MyAppName}"; Filename: "{uninstallexe}"
; Shortcut trên Desktop (nếu người dùng chọn)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Chạy app ngay sau khi cài xong (tuỳ chọn)
Filename: "{app}\{#MyAppExeName}"; Description: "Khởi động {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
