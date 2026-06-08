@echo off
setlocal EnableExtensions
title Keyword Forensic Toolkit
cd /d "%~dp0"

rem Double-click me to launch the toolkit.
rem You can also drag a folder onto this file to search that folder.

set "SCRIPT=%~dp0Restructure-ByKeyword.ps1"
if not exist "%SCRIPT%" (
    echo Could not find Restructure-ByKeyword.ps1 next to this launcher.
    echo Keep both files in the same folder.
    echo.
    pause
    exit /b 1
)

rem If a folder was dragged onto this launcher, use it; otherwise ask.
set "TARGET=%~1"
if not "%TARGET%"=="" goto run

set "DEFAULT=%USERPROFILE%\Desktop"
echo.
echo   Keyword Forensic Toolkit
echo   ------------------------
echo.
set /p "TARGET=Folder to search [%DEFAULT%]: "
if "%TARGET%"=="" set "TARGET=%DEFAULT%"

:run
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Path "%TARGET%"
echo.
echo   Toolkit closed. Press any key to exit.
pause >nul
