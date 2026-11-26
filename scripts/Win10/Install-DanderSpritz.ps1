<#  
    .SYNOPSIS  
    Install DanderSpritz and Fuzzbunch

    .DESCRIPTION  
    Author: Francisco Donoso (@francisckrs)
    License: MIT

#>

Set-StrictMode -Version Latest


Try
{
    $eqtools = 'C:\Users\vagrant\eqtools'
    $zip = 'C:\Windows\Temp\EQGRP_Lost_in_Translation-master.zip'
    if (Test-Path $zip) {
        # Offline: expand the pre-staged archive (baked onto the tools CD) so
        # the guest needs neither git nor internet for the toolset.
        $tmp = 'C:\Windows\Temp\eqgrp_extract'
        if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        # GitHub archives nest everything under a single <repo>-<ref> folder;
        # flatten it so eqtools\windows (etc.) line up with the clone layout.
        $inner = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
        if (Test-Path $eqtools) { Remove-Item -Recurse -Force $eqtools }
        Move-Item -LiteralPath $inner.FullName -Destination $eqtools
    }
    else {
        #Fall back to cloning the git repo into eqtools
        git clone https://github.com/x0rz/EQGRP_Lost_in_Translation.git $eqtools
    }
}
Catch
{
    Write-Host "Failed to obtain EQ tools (zip or clone)...exiting"
    Exit 1
}

Try 
{
	#Create files and directories needed that are not in the repo
    echo $null >> C:\Users\vagrant\eqtools\windows\DSZOpsDisk-1.zip

    mkdir C:\Users\vagrant\eqtools\windows\listeningposts
}
Catch 
{
    Write-Host "Failed to create directories required for DanderSpritz and Fuzzbunch...exiting"  
    Exit 1
}

Try 
{
	# Allow the DanderSpritz javaw exe through the firewall
    netsh advfirewall firewall add rule name="DSZ in" dir=in action=allow program="C:\windows\syswow64\javaw.exe" enable=yes
}
Catch 
{
    Write-Host "Failed to create inbound DSZ firewall rule"  
}
