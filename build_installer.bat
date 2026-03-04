@echo off
setlocal enabledelayedexpansion

:: Configuration
set APP_NAME=QuizDat
set PROJECT_DIR=%~dp0Front-end\QuizDat
set INSTALLER_SCRIPT=%~dp0QuizDat_Installer.iss
set ISCC="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

echo [1/5] Cleaning old build artifacts...
if exist "%PROJECT_DIR%\build" rd /s /q "%PROJECT_DIR%\build"

echo [2/5] Running flutter pub get...
cd /d "%PROJECT_DIR%"
call flutter pub get
if %ERRORLEVEL% neq 0 (echo Error: flutter pub get failed & exit /b 1)

echo [3/5] Converting icon...
powershell -ExecutionPolicy Bypass -File "convert_icon.ps1"
if %ERRORLEVEL% neq 0 (echo Error: icon conversion failed & exit /b 1)

echo [4/5] Building Windows Release app...
call flutter build windows --release
if %ERRORLEVEL% neq 0 (echo Error: flutter build failed & exit /b 1)

echo [5/5] Compiling Inno Setup Installer...
cd /d "%~dp0"
if exist %ISCC% (
    %ISCC% "%INSTALLER_SCRIPT%"
    if %ERRORLEVEL% neq 0 (echo Error: Installer compilation failed & exit /b 1)
) else (
    echo [WARNING] Inno Setup Compiler not found at %ISCC%. 
    echo Please install Inno Setup 6 or update the path in this script.
    exit /b 1
)

echo.
echo ======================================================
echo Success! Your installer is ready: %~dp0QuizDat_Setup.exe
echo ======================================================
pause
