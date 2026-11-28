@echo off
rem ---------------------------------------------------------------------------
rem PowerShell 5.1 bootstrap for a cold Windows 7 / Server 2008 R2 box (PS 2.0),
rem run from the tools CD at first logon. Modern ansible.windows requires PS 5.1,
rem so this installs .NET 4.5.2 then WMF 5.1 (both sit next to this script, so
rem %~dp0 locates them with no drive-letter guessing), then reboots. On the next
rem boot the box runs PS 5.1 and Ansible can manage it.
rem
rem UI: .NET uses /passive (a progress window, still unattended) so whoever is
rem watching the Proxmox console sees activity. wusa (WMF) has no progress-only
rem mode -- /quiet is silent and a non-quiet install would STOP for a click and
rem hang this unattended logon -- so WMF stays /quiet with echo feedback instead.
rem Re-running is harmless: both installers no-op if already applied.
rem ---------------------------------------------------------------------------

echo.
echo ============================================================
echo   DanderSpritz lab - PowerShell 5.1 bootstrap
echo   Windows 7 / Server 2008 R2 ships PS 2.0; installing the
echo   prerequisites now. This takes several minutes - please wait.
echo ============================================================
echo.

echo [1/2] Installing .NET Framework 4.5.2 (a progress window will appear) ...
start /wait "" "%~dp0NDP452-KB2901907-x86-x64-AllOS-ENU.exe" /passive /norestart
echo       .NET Framework 4.5.2 install finished.
echo.

echo [2/2] Installing WMF 5.1 / PowerShell 5.1 via wusa (silent - wusa has no
echo       progress-only mode; this runs a few minutes with no window) ...
start /wait "" "wusa.exe" "%~dp0Win7AndW2K8R2-KB3191566-x64.msu" /quiet /norestart
echo       WMF 5.1 install finished.
echo.

echo Rebooting in 30s to activate PowerShell 5.1 ...
shutdown /r /t 30 /c "Activating PowerShell 5.1 (DanderSpritz lab bootstrap)"
