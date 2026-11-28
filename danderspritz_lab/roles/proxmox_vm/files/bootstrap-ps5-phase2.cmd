@echo off
rem ---------------------------------------------------------------------------
rem PowerShell 5.1 bootstrap - phase 2. Installs .NET 4.5.2 then WMF 5.1 from
rem C:\Windows\Temp (staged by phase 1 / bootstrap-ps5.cmd), then reboots so the
rem box comes up on PS 5.1. Invoked either inline (box already SP1) or via the
rem RunOnce phase 1 armed after the SP1 reboot. Uses fixed C: paths so it does
rem not depend on the CD drive letter after a reboot.
rem ---------------------------------------------------------------------------
set "T=C:\Windows\Temp"

echo [bootstrap] Installing .NET Framework 4.5.2 (progress window) ...
start /wait "" "%T%\NDP452-KB2901907-x86-x64-AllOS-ENU.exe" /passive /norestart

echo [bootstrap] Waiting for .NET 4.5.2 to register (WMF 5.1 requires it) ...
set /a _tries=0
:waitnet
reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" /v Release >nul 2>&1 && goto netok
set /a _tries+=1
if %_tries% geq 30 goto netok
ping -n 11 127.0.0.1 >nul
goto waitnet
:netok

echo [bootstrap] Installing WMF 5.1 / PowerShell 5.1 (silent) ...
start /wait "" "wusa.exe" "%T%\Win7AndW2K8R2-KB3191566-x64.msu" /quiet /norestart

echo [bootstrap] Rebooting to activate PowerShell 5.1 ...
shutdown /r /t 30 /c "Activating PowerShell 5.1"
