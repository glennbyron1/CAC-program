# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Builds the lab Certificate Authority and the Smart Card Group Policy
    Object. Run AFTER Build-CAC-Lab.ps1 has promoted the domain controller
    and the server has rebooted.

.DESCRIPTION
    This script stages the lab-side AD CS deployment and the smart-card
    GPO baseline described in the Architecture/Blueprint.md document.

    Concretely, it:
      1. Installs the AD CS Certificate Authority role.
      2. Configures the server as an Enterprise Root CA (LAB SIMPLICITY -
         in production this would be an Enterprise Subordinate CA signed
         by an offline Standalone Root CA; see Architecture/Blueprint.md).
      3. Creates the SmartCard-Pilot OU.
      4. Creates the "SmartCard Policy" GPO with lock-on-removal enabled.
      5. Links the GPO to the SmartCard-Pilot OU (scoped pilot, not domain
         root - prevents accidental org-wide enforcement).
      6. Publishes an initial CRL.

    The script is intentionally LAB-FOCUSED. It uses sane defaults for a
    throwaway lab environment. For production, see Architecture/Blueprint.md
    Section 2 for the two-tier hierarchy and Group-Policy/Enforce-SmartCard.ps1
    for the production-grade GPO settings.

.PARAMETER CAName
    Common name to use for the lab CA. Defaults to LAB-CA.

.PARAMETER DomainDistinguishedName
    Distinguished name of the lab domain. Defaults to DC=lab,DC=local.

.PARAMETER PilotOUName
    Name of the pilot OU. Defaults to SmartCard-Pilot.

.PARAMETER GPOName
    Name of the GPO to create. Defaults to "SmartCard Policy".

.EXAMPLE
    .\Build-CA-GPO.ps1

.EXAMPLE
    .\Build-CA-GPO.ps1 -CAName "LAB-ICA01" -DomainDistinguishedName "DC=lab,DC=local"

.NOTES
    File Name      : Build-CA-GPO.ps1
    Author         : Glenn Byron
    Framework Path : NIST SP 800-53 Rev. 5 (IA-2, IA-2(11), AC-11)
    Security Tier  : Sanitized lab / pilot deployment - NOT production-ready.
    Prerequisites  : Build-CAC-Lab.ps1 has run, server has rebooted, and the
                     server is operating as a domain controller for the lab
                     forest.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$CAName                  = "LAB-CA",
    [string]$DomainDistinguishedName = "DC=lab,DC=local",
    [string]$PilotOUName             = "SmartCard-Pilot",
    [string]$GPOName                 = "SmartCard Policy",
    [string]$LogPath                 = "C:\Windows\Logs\ICAM_CA_GPO_Deployment.log"
)

Start-Transcript -Path $LogPath -Append

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " BUILDING LAB CERTIFICATE AUTHORITY + SMART CARD GPO"               -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " CA Name             : $CAName"                                     -ForegroundColor White
Write-Host " Domain DN           : $DomainDistinguishedName"                    -ForegroundColor White
Write-Host " Pilot OU            : $PilotOUName"                                -ForegroundColor White
Write-Host " GPO Name            : $GPOName"                                    -ForegroundColor White
Write-Host " NIST Controls       : IA-2, IA-2(11), AC-11"                       -ForegroundColor White
Write-Host ""

# ------------------------------------------------------------------
# Admin elevation check
# ------------------------------------------------------------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrative elevation is required. Relaunch the shell as Administrator."
    Stop-Transcript
    exit 1
}

# ------------------------------------------------------------------
# 1. Install AD CS role
# ------------------------------------------------------------------
Write-Host "[1/5] Installing AD CS Certificate Authority role..." -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("Server", "Install ADCS-Cert-Authority role")) {
    try {
        Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools | Out-Null
        Write-Host "    -> AD CS role installed." -ForegroundColor Green
    } catch {
        Write-Error "AD CS role install failed: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}

# ------------------------------------------------------------------
# 2. Configure as Enterprise Root CA (LAB ONLY - see Blueprint.md for prod)
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[2/5] Configuring Enterprise Root CA (lab simplicity)..." -ForegroundColor Cyan
Write-Host "    NOTE: In production, configure as Enterprise Subordinate CA" -ForegroundColor Yellow
Write-Host "          signed by an offline Standalone Root. See Blueprint.md." -ForegroundColor Yellow

if ($PSCmdlet.ShouldProcess($CAName, "Install Enterprise Root CA")) {
    try {
        Install-AdcsCertificationAuthority `
            -CAType EnterpriseRootCA `
            -CACommonName $CAName `
            -KeyLength 2048 `
            -HashAlgorithmName SHA256 `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -Force -ErrorAction Stop | Out-Null
        Write-Host "    -> CA configured." -ForegroundColor Green
    } catch {
        Write-Error "CA configuration failed: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}

# ------------------------------------------------------------------
# 3. Create the SmartCard-Pilot OU
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[3/5] Creating pilot OU '$PilotOUName'..." -ForegroundColor Cyan
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "ActiveDirectory module not available. Confirm the server is a DC."
    Stop-Transcript
    exit 1
}

$existingOU = Get-ADOrganizationalUnit -Filter "Name -eq '$PilotOUName'" -ErrorAction SilentlyContinue
if ($existingOU) {
    Write-Host "    -> OU already exists: $($existingOU.DistinguishedName)" -ForegroundColor Yellow
} elseif ($PSCmdlet.ShouldProcess("OU=$PilotOUName,$DomainDistinguishedName", "Create OU")) {
    try {
        New-ADOrganizationalUnit -Name $PilotOUName -Path $DomainDistinguishedName -ProtectedFromAccidentalDeletion $true
        Write-Host "    -> Created OU=$PilotOUName,$DomainDistinguishedName" -ForegroundColor Green
    } catch {
        Write-Error "OU creation failed: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
}

# ------------------------------------------------------------------
# 4. Create the SmartCard GPO with lock-on-removal
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[4/5] Creating GPO '$GPOName' (lock-on-removal)..." -ForegroundColor Cyan
Import-Module GroupPolicy -ErrorAction Stop

$existingGPO = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
if ($existingGPO) {
    Write-Host "    -> GPO already exists. Reusing: $GPOName" -ForegroundColor Yellow
    $gpo = $existingGPO
} elseif ($PSCmdlet.ShouldProcess($GPOName, "Create GPO")) {
    $gpo = New-GPO -Name $GPOName -Comment "Lab pilot: lock workstation on smart card removal (NIST AC-11)."
    Write-Host "    -> GPO created." -ForegroundColor Green
}

if ($gpo) {
    if ($PSCmdlet.ShouldProcess($GPOName, "Configure smart card removal behavior = Lock Workstation")) {
        Set-GPRegistryValue `
            -Name $gpo.DisplayName `
            -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "ScRemoveOption" `
            -Type DWord `
            -Value 1 | Out-Null
        Write-Host "    -> ScRemoveOption = 1 (Lock Workstation) set." -ForegroundColor Green
        Write-Host "       NOTE: 'Require smart card' (scforceoption) is NOT set here." -ForegroundColor Gray
        Write-Host "             Enforcement is layered later via Group-Policy/Enforce-SmartCard.ps1." -ForegroundColor Gray
    }

    # Link to the pilot OU, NOT to the domain root.
    $linkTarget = "OU=$PilotOUName,$DomainDistinguishedName"
    if ($PSCmdlet.ShouldProcess($linkTarget, "Link GPO '$GPOName'")) {
        try {
            New-GPLink -Name $gpo.DisplayName -Target $linkTarget -ErrorAction Stop | Out-Null
            Write-Host "    -> GPO linked to $linkTarget" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -match "already linked") {
                Write-Host "    -> GPO already linked to $linkTarget" -ForegroundColor Yellow
            } else {
                Write-Warning "GPO link failed: $($_.Exception.Message)"
            }
        }
    }
}

# ------------------------------------------------------------------
# 5. Publish initial CRL
# ------------------------------------------------------------------
Write-Host ""
Write-Host "[5/5] Publishing initial CRL..." -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess($CAName, "Publish initial CRL")) {
    try {
        & certutil -crl | Out-Null
        Write-Host "    -> CRL published." -ForegroundColor Green
    } catch {
        Write-Warning "CRL publish reported an issue: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " DEPLOYMENT COMPLETE - LAB CA + SMART CARD GPO READY"               -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Next steps:"
Write-Host "   1. Verify CA service:        Get-Service certsvc | Format-Table"
Write-Host "   2. List published templates: certutil -catemplates"
Write-Host "   3. Validate GPO link:        Get-GPInheritance -Target '$linkTarget'"
Write-Host "   4. Issue a test cert from the SmartCard-Logon template"
Write-Host "      against a member of the SmartCard-Pilot group, then test"
Write-Host "      lock-on-removal at a pilot endpoint."
Write-Host ""
Write-Host " Transcript log: $LogPath"

Stop-Transcript
