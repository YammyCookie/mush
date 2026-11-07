@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Publish-Website.ps1"
if errorlevel 1 echo The website was not published. Read the message above for the next step.
pause
