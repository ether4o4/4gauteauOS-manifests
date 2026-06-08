@echo off
setlocal
cd /d "%~dp0"
title Digital Footprint - Quick

rem The simple version: no Python, no installs. Double-click me.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Footprint-Quick.ps1"

echo.
echo   Done. Your report opened in the browser and is saved in your
echo   Desktop "digital footprint" folder. Press any key to close.
pause >nul
