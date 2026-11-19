@echo off
rem Double-click to publish a new Sunder build. Extra arguments pass through, e.g.
rem   publish.bat -Notes "Faster staff heavies"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
echo.
pause
