<#
    .SYNOPSIS
    Installs Windows 7 SP1 (KB976932) from a pre-staged, verified installer.

    .DESCRIPTION
    Author: Francisco Donoso (@francisckrs)
    License: MIT

    Installs Windows 7 SP1 from C:\Windows\Temp\KB976932-X64.exe. The Ansible
    target role places and SHA-256-verifies that file first (from the tools CD
    or a checksum-verified download), so this script neither downloads nor
    re-verifies — it just runs the installer.

    .NOTES
    Microsoft removed the original download-center file, so acquisition and
    verification moved into the target role (group_vars/all.yml: sp1_url /
    sp1_sha256). This script failing on a missing file means the role's
    acquisition step did not run or did not succeed.
#>

Set-StrictMode -Version Latest

$installer = 'C:\Windows\Temp\KB976932-X64.exe'

Try
{
  if (-not (Test-Path $installer))
  {
    Write-Host "SP1 installer not found at $installer. The target role stages/verifies it before this script runs."
    Exit 1
  }

  Write-Host "Starting SP1 installation from $installer. Hang on, this will take a long time."
  Start-Process -FilePath $installer -ArgumentList "/quiet", "/nodialog", "/norestart" -Wait
}
Catch
{
  Write-Host "Fatal error installing Service Pack 1. Exiting."
  Write-Host $_.Exception | format-list -force
  Exit 1
}
