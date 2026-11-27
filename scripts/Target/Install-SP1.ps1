<#
    .SYNOPSIS
    Installs Windows 7 SP1 (KB976932).

    .DESCRIPTION
    Author: Francisco Donoso (@francisckrs)
    License: MIT

    Installs Windows 7 SP1. Uses the installer staged at
    C:\Windows\Temp\KB976932-X64.exe (placed there from the tools CD by the
    Ansible target role) if present; otherwise downloads it.

    .NOTES
    Microsoft removed the original download-center file, so the live fallback
    now points at the Internet Archive's copy of the same binary rather than the
    dead download.microsoft.com URL. Preferred delivery is the vendored copy on
    the tools CD (see group_vars/all.yml: fetch_sp1 / sp1_url).
#>

Set-StrictMode -Version Latest

$dest = 'C:\Windows\Temp\KB976932-X64.exe'
$url = 'https://web.archive.org/web/20110608170121id_/http://download.microsoft.com/download/0/A/F/0AFB5316-3062-494A-AB78-7FB0D4461357/windows6.1-KB976932-X64.exe'

Try
{
  if (Test-Path $dest)
  {
    Write-Host "SP1 installer already staged at $dest (from the tools CD). Skipping download."
  }
  else
  {
    Write-Host "SP1 installer not staged; downloading from the Internet Archive (Microsoft removed the original). This is ~903 MB and will take a while."
    (New-Object System.Net.WebClient).DownloadFile($url, $dest)
    Write-Host "Successfully downloaded SP1."
  }

  Write-Host "Starting SP1 installation. Hang on, this will take a long time."
  Start-Process -FilePath $dest -ArgumentList "/quiet", "/nodialog", "/norestart" -Wait
}
Catch
{
  Write-Host "Fatal error installing Service Pack 1. Exiting."
  Write-Host $_.Exception | format-list -force
  Exit 1
}
