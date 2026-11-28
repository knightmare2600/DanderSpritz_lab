@echo off
rem ---------------------------------------------------------------------------
rem PowerShell 5.1 bootstrap, run from the tools CD at first logon. Modern
rem ansible.windows needs PS 5.1 -> WMF 5.1 -> .NET 4.5.2.
rem
rem On Windows 7 RTM, WMF 5.1 is "not applicable" until SP1 is installed AND the
rem box has rebooted, so RTM takes a TWO-PHASE path:
rem   phase 1 (this script): stage installers to C:, arm a RunOnce for phase 2,
rem            install SP1, reboot.
rem   phase 2 (bootstrap-ps5-phase2.cmd, via that RunOnce after the SP1 reboot):
rem            install .NET 4.5.2 + WMF 5.1, reboot -> PS 5.1.
rem A box already at SP1 (Server 2008 R2 SP1) skips SP1 and runs phase 2 inline.
rem
rem Installers are copied to C:\Windows\Temp so phase 2 needs neither the CD
rem drive letter nor it staying the same across the reboot. %~dp0 = this CD.
rem ---------------------------------------------------------------------------
setlocal
set "T=C:\Windows\Temp"

echo [bootstrap] Staging installers to %T% ...
copy /y "%~dp0NDP452-KB2901907-x86-x64-AllOS-ENU.exe" "%T%\" >nul
copy /y "%~dp0Win7AndW2K8R2-KB3191566-x64.msu" "%T%\" >nul
copy /y "%~dp0bootstrap-ps5-phase2.cmd" "%T%\" >nul

rem Already Service Pack 1? (Win7 SP1 or Server 2008 R2 SP1 report it here.)
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CSDVersion 2>nul | find "Service Pack 1" >nul
if not errorlevel 1 goto havesp1

echo [bootstrap] Windows 7 RTM detected - installing SP1 first (phase 1 of 2).
echo [bootstrap] PowerShell 5.1 installs automatically after the SP1 reboot.
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v DszPs5Phase2 /t REG_SZ /d "%T%\bootstrap-ps5-phase2.cmd" /f >nul
start /wait "" "%~dp0windows6.1-KB976932-X64.exe" /quiet /nodialog /norestart
echo [bootstrap] SP1 staged; rebooting to finalise it (this boot is slow) ...
shutdown /r /t 30 /c "Installing Windows 7 SP1 (phase 1 of 2)"
goto end

:havesp1
echo [bootstrap] SP1 already present - installing PowerShell 5.1 now.
call "%T%\bootstrap-ps5-phase2.cmd"

:end
endlocal
