#Requires -Version 5.1
#Requires -Modules ActiveDirectory, GroupPolicy
<#
.SYNOPSIS
    Phase 8.2.2 - Triggers fleet-wide autoenrollment for the ZT device cert
    template created by New-DeviceCertTemplate.ps1.

.DESCRIPTION
    Creates a "ZT-Autoenroll-Device-Certs" GPO scoped to Domain Computers
    that enables Computer Configuration certificate autoenrollment and
    sets the renewal trigger.

    Then runs a remote `gpupdate /force` + `certutil -pulse` on each
    machine to force immediate enrollment instead of waiting for the
    8-hour autoenroll cycle.

.PARAMETER TemplateName
    Must match the template created in 8.2.1. Default 'ZT-Device-Authentication'.

.PARAMETER Computers
    Array of computer names to force-pulse. Default - all domain computers.

.PARAMETER DryRun
    Switch - preview without writing.

.EXAMPLE
    .\Enroll-DeviceCertificates.ps1

.EXAMPLE
    # Only force on these two for now
    .\Enroll-DeviceCertificates.ps1 -Computers 'Lab-DC01','Lab-Workstation01'

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.2.2 - Device Trust
    Depends on : New-DeviceCertTemplate.ps1 (template ZT-Device-Authentication)
    NIST       : IA-3, IA-3(1), IA-5(2)
    Last Edit  : 2026-06-03
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TemplateName = 'ZT-Device-Authentication',
    [string[]]$Computers  = @(),
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Skip  { param([string]$msg) Write-Host "  [SKIP] $msg"   -ForegroundColor DarkGray }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |     Phase 8.2.2 - Enroll Device Certs (fleet)        |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy    -ErrorAction Stop

# Create / locate the autoenroll GPO
$gpoName = 'ZT-Autoenroll-Device-Certs'
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    if ($PSCmdlet.ShouldProcess($gpoName, 'New-GPO')) {
        if (-not $DryRun) {
            $gpo = New-GPO -Name $gpoName -Comment 'Phase 8.2.2 - autoenrollment for ZT device certs'
        }
        Write-OK "Created GPO: $gpoName"
    }
} else {
    Write-Skip "GPO exists: $gpoName"
}

if (-not $DryRun) {
    # Computer Configuration -> Policies -> Windows Settings -> Security Settings ->
    # Public Key Policies -> Certificate Services Client - Auto-Enrollment
    # Registry equivalent (HKLM):
    $key = 'HKLM\Software\Policies\Microsoft\Cryptography\AutoEnrollment'
    Set-GPRegistryValue -Name $gpoName -Key $key -ValueName 'AEPolicy' -Type DWord -Value 7 | Out-Null
    # 7 = enabled + renew expired + update pending + update from template

    # Link to domain root
    $domainDn = (Get-ADDomain).DistinguishedName
    $linked = (Get-GPInheritance -Target $domainDn).GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
    if (-not $linked) {
        New-GPLink -Name $gpoName -Target $domainDn -Enforced No -LinkEnabled Yes | Out-Null
        Write-OK "Linked $gpoName to $domainDn"
    } else {
        Write-Skip "$gpoName already linked to domain root"
    }
}
Write-Host ''

# Determine target computers
if ($Computers.Count -eq 0) {
    $Computers = (Get-ADComputer -Filter * -Properties Enabled |
                  Where-Object { $_.Enabled }).Name
}
Write-Step "Pulsing $($Computers.Count) computer(s) to trigger immediate enrollment..."
Write-Host ''

$results = @()
foreach ($c in $Computers) {
    Write-Step "$c"
    try {
        if ($DryRun) {
            Write-Host "       (DryRun) Would run: gpupdate /force; certutil -pulse" -ForegroundColor DarkGray
            $results += [PSCustomObject]@{ Computer = $c; Status = 'DryRun' }
            continue
        }
        Invoke-Command -ComputerName $c -ScriptBlock {
            gpupdate /force | Out-Null
            certutil -pulse | Out-Null
        } -ErrorAction Stop
        Write-OK "$c pulsed"
        $results += [PSCustomObject]@{ Computer = $c; Status = 'OK' }
    } catch {
        Write-Warn "$c failed: $($_.Exception.Message.Split([char]10)[0])"
        $results += [PSCustomObject]@{ Computer = $c; Status = "FAIL: $($_.Exception.Message.Split([char]10)[0])" }
    }
}
Write-Host ''

# Brief wait for AD CS to issue
if (-not $DryRun) {
    Write-Step 'Waiting 30 seconds for CA to issue certs...'
    Start-Sleep -Seconds 30
}

# Verify
Write-Step 'Verifying issued certs in AD CS database...'
$caComputer = (Get-ADDomainController).HostName | Select-Object -First 1
try {
    $issued = certutil -view -restrict "CertificateTemplate=$TemplateName,Disposition=20" -out 'RequesterName,NotAfter' csv 2>$null |
              Where-Object { $_ -and $_ -notlike '*Schema*' -and $_ -notlike '*Row*' }
    if ($issued) {
        Write-OK "$($issued.Count) cert(s) issued for $TemplateName"
    } else {
        Write-Warn 'No issued certs found yet - may take a few more minutes'
    }
} catch {
    Write-Warn "Could not query AD CS database from this session: $($_.Exception.Message.Split([char]10)[0])"
}

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
$results | Format-Table -AutoSize | Out-Host
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Verify on each endpoint: certutil -store -v MY' -ForegroundColor Yellow
Write-Host '  Look for issuer = LAB-CA and EKU = Client Authentication' -ForegroundColor Yellow
Write-Host ''
