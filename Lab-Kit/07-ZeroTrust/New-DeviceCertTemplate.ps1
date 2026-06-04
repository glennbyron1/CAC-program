#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.2.1 - Creates a Device (machine) certificate template on the
    Issuing CA. Used by Enroll-DeviceCertificates.ps1 to give every
    domain-joined computer a machine identity cert.

.DESCRIPTION
    Duplicates the built-in "Workstation Authentication" template, names it
    "ZT-Device-Authentication", and tightens it for ZT use:
      - 1-year validity, 6-week renewal window
      - Subject built from AD computer DNS name
      - Subject Alternative Name = DNS = computer.lab.local
      - EKU: Client Authentication only (no Server Auth)
      - Key: 2048 RSA, Microsoft Software KSP (TPM KSP if -UseTPM)
      - Autoenrollment enabled for Domain Computers

    These device certs become the device half of mutual cert auth
    (used by Update-VPN-DeviceAuth.ps1 in 8.2.4) and the device-trust
    signal for Conditional Access (8.3.2).

.PARAMETER TemplateName
    Display name for the new template. Default 'ZT-Device-Authentication'.

.PARAMETER ValidityYears
    Cert validity in years. Default 1.

.PARAMETER RenewalWeeks
    Renewal window in weeks before expiry. Default 6.

.PARAMETER UseTPM
    Switch - require the TPM Key Storage Provider. Bind the cert key to
    hardware. Recommended for production. Requires TPM 2.0 on every endpoint.

.PARAMETER DryRun
    Switch - preview without writing to AD.

.EXAMPLE
    .\New-DeviceCertTemplate.ps1

.EXAMPLE
    .\New-DeviceCertTemplate.ps1 -UseTPM -ValidityYears 2

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.2.1 - Device Trust
    Depends on : Working Issuing CA (Build-CA-GPO.ps1 already run)
    Module     : Uses PSPKI (Install-Module PSPKI on the DC)
    NIST       : IA-3, IA-3(1)
    Last Edit  : 2026-06-03
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TemplateName  = 'ZT-Device-Authentication',
    [int]   $ValidityYears = 1,
    [int]   $RenewalWeeks  = 6,
    [switch]$UseTPM,
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
Write-Host '  |     Phase 8.2.1 - Device Cert Template (ZT)          |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# Verify PSPKI is installed
if (-not (Get-Module -ListAvailable PSPKI)) {
    Write-Fatal 'PSPKI module not available. Install-Module PSPKI on Lab-DC01 (already done in Phase 6 if you followed the docs).'
}
Import-Module PSPKI -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

# Check we have an Enterprise CA
$ca = Get-CertificationAuthority -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ca) {
    Write-Fatal 'No Enterprise CA found. Run Build-CA-GPO.ps1 first.'
}
Write-OK "Issuing CA: $($ca.DisplayName) on $($ca.ComputerName)"

# Source template = built-in WorkstationAuthentication
$srcName = 'Workstation Authentication'
$src = Get-CertificateTemplate -Name $srcName -ErrorAction SilentlyContinue
if (-not $src) {
    Write-Fatal "Source template '$srcName' not found in AD."
}
Write-OK "Source template: $srcName"

# Check if target already exists
$exists = Get-CertificateTemplate -Name $TemplateName -ErrorAction SilentlyContinue
if ($exists) {
    Write-Skip "Template '$TemplateName' already exists. Re-running this script will reuse it."
} else {
    if ($PSCmdlet.ShouldProcess($TemplateName, "Clone from $srcName")) {
        if (-not $DryRun) {
            # PSPKI doesn't have native template-duplication but we can copy attributes
            $cfgNC = (Get-ADRootDSE).configurationNamingContext
            $srcDn = "CN=$($src.CommonName),CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
            $newDn = "CN=$TemplateName,CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"

            $srcObj = Get-ADObject -Identity $srcDn -Properties *
            $attrs = @{}
            $skipAttrs = @('distinguishedName','objectGUID','objectCategory','objectClass','cn','name','whenCreated','whenChanged','uSNCreated','uSNChanged','msPKI-Cert-Template-OID')
            foreach ($p in $srcObj.PSObject.Properties) {
                if ($skipAttrs -notcontains $p.Name -and $null -ne $p.Value -and $p.Name -notlike '*Object*') {
                    $attrs[$p.Name] = $p.Value
                }
            }
            $attrs['displayName'] = $TemplateName

            New-ADObject -Name $TemplateName `
                -Type 'pKICertificateTemplate' `
                -Path "CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC" `
                -OtherAttributes $attrs

            Write-OK "Cloned: $TemplateName"
        }
    }
}

if ($DryRun) {
    Write-Warn 'DryRun mode - skipping property tuning and publishing'
    return
}

# Tune the new template
$tpl = Get-CertificateTemplate -Name $TemplateName

# Validity + renewal
$tpl.Settings.ValidityPeriod = New-Object TimeSpan ($ValidityYears * 365), 0, 0, 0
$tpl.Settings.RenewalPeriod  = New-Object TimeSpan ($RenewalWeeks  * 7),   0, 0, 0

# Force re-enroll cycle for autoenrollment
$tpl.Settings.RegistrationAuthority.SignatureCount = 0

# Key length and provider
$tpl.Settings.Cryptography.MinimalKeyLength = 2048
$tpl.Settings.Cryptography.CSPList.Clear()
if ($UseTPM) {
    $tpl.Settings.Cryptography.CSPList.Add('Microsoft Platform Crypto Provider')
    Write-OK 'Key Storage Provider: TPM (Microsoft Platform Crypto Provider)'
} else {
    $tpl.Settings.Cryptography.CSPList.Add('Microsoft Software Key Storage Provider')
    Write-OK 'Key Storage Provider: Software'
}

$tpl.Settings.Cryptography.KeyAlgorithm = 'RSA'
$tpl.Commit()
Write-OK 'Template tuned (validity, renewal, key)'

# Publish to CA
$published = Get-CATemplate -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $TemplateName -or $_.Name -eq $TemplateName }
if (-not $published) {
    Add-CATemplate -Name $TemplateName -Force
    Write-OK "Published $TemplateName to CA"
} else {
    Write-Skip "$TemplateName already published"
}

# Grant Domain Computers Read + Enroll + AutoEnroll
$tpl = Get-CertificateTemplate -Name $TemplateName
$acl = $tpl | Get-CertificateTemplateAcl
$acl | Add-CertificateTemplateAcl -Identity 'Domain Computers' `
        -AccessType Allow -AccessMask Read, Enroll, AutoEnroll | Set-CertificateTemplateAcl | Out-Null
Write-OK 'Granted Domain Computers: Read + Enroll + AutoEnroll'

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    Template ready: $TemplateName" -ForegroundColor White
Write-Host '    Next: Enroll-DeviceCertificates.ps1 to trigger autoenrollment fleet-wide.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
