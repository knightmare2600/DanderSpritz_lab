@echo off
rem ---------------------------------------------------------------------------
rem PowerShell 5.1 bootstrap for a cold Windows 7 / Server 2008 R2 box (PS 2.0),
rem run from the tools CD at first logon. Modern ansible.windows requires PS 5.1,
rem so this installs .NET 4.5.2 then WMF 5.1 (both sit next to this script, so
rem %~dp0 locates them with no drive-letter guessing), then reboots. On the next
rem boot the box runs PS 5.1 and Ansible can manage it.
rem
rem This lives on the CD as a batch file ON PURPOSE: the earlier inline
rem `cmd /c powershell -Command "...| ... | ..."` in the answer file did not run
rem reliably (pipe/quote handling in FirstLogonCommands). A plain .cmd avoids it.
rem Re-running is harmless: both installers no-op if already applied.
rem ---------------------------------------------------------------------------

echo [bootstrap] Installing .NET Framework 4.5.2 (WMF 5.1 prerequisite) ...
start /wait "" "%~dp0NDP452-KB2901907-x86-x64-AllOS-ENU.exe" /q /norestart

echo [bootstrap] Installing WMF 5.1 / PowerShell 5.1 ...
start /wait "" "wusa.exe" "%~dp0Win7AndW2K8R2-KB3191566-x64.msu" /quiet /norestart

echo [bootstrap] Rebooting in 30s to activate PowerShell 5.1 ...
shutdown /r /t 30 /c "Activating PowerShell 5.1 (DanderSpritz lab bootstrap)"
