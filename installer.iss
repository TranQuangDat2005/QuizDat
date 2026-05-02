[Setup]
AppName=QuizDat
AppVersion=1.0
DefaultDirName={autopf}\QuizDat
DefaultGroupName=QuizDat
OutputDir=C:\Users\Admin\Desktop
OutputBaseFilename=quizdat_setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=compiler:SetupClassicIcon.ico

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "C:\Users\Admin\Desktop\QuizDat\Front-end\QuizDat\build\windows\x64\runner\Release\QuizDat.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\Admin\Desktop\QuizDat\Front-end\QuizDat\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\QuizDat"; Filename: "{app}\QuizDat.exe"
Name: "{autodesktop}\QuizDat"; Filename: "{app}\QuizDat.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\QuizDat.exe"; Description: "{cm:LaunchProgram,QuizDat}"; Flags: nowait postinstall skipifsilent
