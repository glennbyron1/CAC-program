# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Builds the lab domain controller: installs AD DS and promotes the server
    to a domain controller for a fresh lab forest. This is the FIRST script
    in the lab build; run Build-CA-GPO.ps1 after the reboot it triggers.

.DESCRIPTION
    Phase B of the lab build (see Architecture/STIG-Hardening-Guide.md and the
    Lab Build Guide). On a clean Windows Server VM this script:
      1. Verifies administrative elevation.
      2. Installs the AD Domain Services role.
      3. Promotes the server to a domain controller, creating a new forest
         (default lab.local) with integrated DNS.
      4. Triggers the required reboot.

    After the server reboots, run Build-CA-GPO.ps1 to install the Certificate
    Authority, create the SmartCard-Pilot OU, build the smart-card GPO, and
    publish the initial CRL.

    LAB ONLY. This creates a brand-new forest and reboots the machine. Never
    run it on a production server or an existing domain controller. Use a
    throwaway VM or dedicated lab hardware, and use the lab.local naming (NOT
    a name derived from your production domain - see the Lab Build Guide).

.PARAMETER DomainName
    FQDN of the new lab forest root domain. Default: lab.local

.PARAMETER NetBIOSName
    NetBIOS name for the new domain. Default: LAB

.PARAMETER SafeModePassword
    Directory Services Restore Mode (DSRM) password as a SecureString. If
    omitted, the script prompts securely. Store the real value in your vault.

.EXAMPLE
    .\Build-CAC-Lab.ps1 -WhatIf

.EXAMPLE
    .\Build-CAC-Lab.ps1 -DomainName "lab.local" -NetBIOSName "LAB"

.NOTES
    File Name      : Build-CAC-Lab.ps1
    Framework      : NIST SP 800-53 Rev. 5 (IA-2, AC-11), FIPS 201-3 alignment
    Security Tier  : Sanitized lab deployment - LAB-SAFE ONLY, NOT production.
    Prerequisite   : Clean Windows Server VM with a static IP and its DNS set
                     to itself (see the Lab Build Guide, Phase B).
    Follow-up      : Build-CA-GPO.ps1 (run after the reboot this triggers).
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$DomainName  = "lab.local",
    [string]$NetBIOSName = "LAB",
    [System.Security.SecureString]$SafeModePassword,
    [string]$LogPath     = "C:\Windows\Logs\ICAM_Lab_DC_Build.log"
)

Start-Transcript -Path $LogPath -Append

Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host " BUILDING LAB DOMAIN CONTROLLER (Phase B)"                              -ForegroundColor Cyan
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host " New forest domain : $DomainName"   -ForegroundColor White
Write-Host " NetBIOS name      : $NetBIOSName"  -ForegroundColor White
Write-Host " NIST controls     : IA-2, AC-11"   -ForegroundColor White
Write-Host ""

# ------------------------------------------------------------------
# Safety guardrails
# ------------------------------------------------------------------
Write-Host "[!] LAB ONLY: this creates a NEW forest and reboots the machine." -ForegroundColor Yellow
Write-Host "    Do not run on production or an existing domain controller."   -ForegroundColor Yellow
Write-Host ""

# Admin elevation check
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrative elevation is required. Relaunch the shell as Administrator."
    Stop-Transcript
    exit 1
}

# Refuse to run if the machine is already a domain controller
try {
    $role = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
    # DomainRole 4 or 5 = backup/primary domain controller
    if ($role -eq 4 -or $role -eq 5) {
        Write-Error "This machine is already a domain controller. Aborting to protect an existing domain."
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Warning "Could not determine domain role; proceeding with caution."
}

# Obtain the DSRM password if not supplied
if (-not $SafeModePassword) {
    Write-Host "Enter a Directory Services Restore Mode (DSRM) password (store it in your vault):" -ForegroundColor White
    $SafeModePassword = Read-Host -AsSecureString
}

# ------------------------------------------------------------------
# 1. Install AD DS role
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[1/3] Installing AD Domain Services role..." -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("This server", "Install AD-Domain-Services role")) {
    try {
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        Write-Host "    -> AD DS role installed." -ForegroundColor Green
    } catch {
        Write-Error "AD DS role install failed: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}

# ------------------------------------------------------------------
# 2. Promote to domain controller (new forest)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[2/3] Promoting to domain controller and creating forest '$DomainName'..." -ForegroundColor Cyan
Write-Host "      The server will reboot automatically when promotion completes." -ForegroundColor Gray

if ($PSCmdlet.ShouldProcess($DomainName, "Create new AD forest and promote to DC")) {
    try {
        Import-Module ADDSDeployment -ErrorAction Stop
        Install-ADDSForest `
            -DomainName $DomainName `
            -DomainNetbiosName $NetBIOSName `
            -SafeModeAdministratorPassword $SafeModePassword `
            -InstallDns:$true `
            -DomainMode "WinThreshold" `
            -ForestMode "WinThreshold" `
            -NoRebootOnCompletion:$false `
            -Force:$true
        # Install-ADDSForest reboots the machine on completion.
    } catch {
        Write-Error "Forest creation failed: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}

# ------------------------------------------------------------------
# 3. Next steps (shown if -WhatIf or if reboot is deferred)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[3/3] Domain controller promotion initiated." -ForegroundColor Green
Write-Host ""
Write-Host " After the server reboots, log in as $NetBIOSName\Administrator and run:" -ForegroundColor Cyan
Write-Host "   .\Build-CA-GPO.ps1" -ForegroundColor White
Write-Host ""
Write-Host " That script installs the Certificate Authority, creates the"  -ForegroundColor Gray
Write-Host " SmartCard-Pilot OU, builds the lock-on-removal GPO, and"        -ForegroundColor Gray
Write-Host " publishes the initial CRL."                                     -ForegroundColor Gray
Write-Host ""
Write-Host " Transcript log: $LogPath" -ForegroundColor Gray

Stop-Transcript
