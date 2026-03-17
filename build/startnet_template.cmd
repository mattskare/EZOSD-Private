@echo off
REM EZOSD Auto-Start Script

wpeinit
start /min cmd
start /min powershell

echo.
echo ============================================================
echo   EZOSD - Enterprise Windows Deployment
echo ============================================================
echo.

REM Set EZOSD environment variable
set EZOSD_USBVer=0.2.1

REM Start the deployment script
echo Starting automated deployment in 5 seconds...
ping -n 5 localhost > NUL
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c > NUL
PowerShell -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod -Uri 'https://github.com/mattskare/EZOSD/releases/latest/download/EZOSD.ps1')"