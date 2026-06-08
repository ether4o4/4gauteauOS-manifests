@echo off
setlocal EnableExtensions
title Digital Footprint Scanner
cd /d "%~dp0"

rem Double-click me to run a scan. On the FIRST run it creates config.json -
rem fill in your details, then double-click again.

where py >nul 2>&1 && (set "PY=py -3") || (set "PY=python")

%PY% "%~dp0footprint.py" %*

echo.
echo   Scan finished. Reports are saved to your Desktop "digital footprint" folder.
echo   Press any key to close.
pause >nul
