$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$Shortcut = $WshShell.CreateShortcut("$DesktopPath\QuizDat.lnk")

# Assuming the app is in the same directory as the script or in a subfolder
$AppPath = Join-Path $PSScriptRoot "Front-end\QuizDat\build\windows\x64\runner\Release"
$Shortcut.TargetPath = Join-Path $AppPath "QuizDat.exe"
$Shortcut.WorkingDirectory = $AppPath
$Shortcut.Description = "QuizDat Application"
$Shortcut.Save()
Write-Host "Shortcut created at $DesktopPath\QuizDat.lnk"
