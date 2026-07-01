#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.4.1 - Creates a short-lived "workload identity" certificate template
    on the Issuing CA for services, apps and scripts that must authenticate as
    themselves (non-person identity) rather than as a user.

.DESCRIPTION
    Mirrors New-DeviceCertTemplate.ps1 (8.2.1) but for workloads:
      - Short validity (default 90 days) with an aggressive renewal window so a
        leaked workload cert ages out fast - the NPI analogue of short-lived
        tokens.
      - EKU: Client Authentication AND Server Authentication, so the same cert
        works for both ends of mutual TLS (used by Enable-mTLS.ps1, 8.4.3).
      - Subject supplied in the request (CN = service identity), key 2048 RSA in
        the Microsoft Software KSP (or TPM with -UseTPM).
      - Enroll permission granted to a dedicated 'Workload-Identities' group, NOT
        Domain Computers - workloads opt in by group membership.

    Re-running is safe; an existing template is reused and re-tuned.

.PARAMETER TemplateName
    Display name for the template. Default 'ZT-Workload-Identity'.

.PARAMETER ValidityDays
    Cert validity in days. Default 90.

.PARAMETER RenewalDays
    Renewal window in days before expiry. Default 14.

.PARAMETER EnrollGroup
    Group granted Read+Enroll. Created if missing. Default 'Workload-Identities'.

.PARAMETER UseTPM
    Switch - bind the key to the TPM (Microsoft Platform Crypto Provider).

.PARAMETER DryRun
    Switch - preview without writing to AD.

.EXAMPLE
    .\New-WorkloadCertTemplate.ps1

.EXAMPLE
    .\New-WorkloadCertTemplate.ps1 -ValidityDays 30 -RenewalDays 7

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.4.1 - Workload / NPI (optional)
    Run on     : Lab-DC01
    Depends on : Working Issuing CA (Build-CA-GPO.ps1), PSPKI module
    NIST       : IA-3, IA-5(2), SA-9
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TemplateName = 'ZT-Workload-Identity',
    [int]   $ValidityDays = 90,
    [int]   $RenewalDays  = 14,
    [string]$EnrollGroup  = 'Workload-Identities',
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
Write-Host '  |   Phase 8.4.1 - Workload Identity Cert Template      |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

if (-not (Get-Module -ListAvailable PSPKI)) {
    Write-Fatal 'PSPKI module not available. Install-Module PSPKI on Lab-DC01 (done in Phase 6 if you followed the docs).'
}
Import-Module PSPKI -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

$ca = Get-CertificationAuthority -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ca) { Write-Fatal 'No Enterprise CA found. Run Build-CA-GPO.ps1 first.' }
Write-OK "Issuing CA: $($ca.DisplayName) on $($ca.ComputerName)"

# Ensure the enroll group exists
$grp = $null
try { $grp = Get-ADGroup -Identity $EnrollGroup -ErrorAction SilentlyContinue } catch {}
if (-not $grp) {
    if ($PSCmdlet.ShouldProcess($EnrollGroup, 'Create enroll group')) {
        if (-not $DryRun) {
            New-ADGroup -Name $EnrollGroup -SamAccountName $EnrollGroup -GroupCategory Security `
                -GroupScope Global -Path (Get-ADDomain).ComputersContainer `
                -Description 'Phase 8.4.1 - principals allowed to enroll workload identity certs'
        }
        Write-OK "Created enroll group: $EnrollGroup"
    }
} else {
    Write-Skip "Enroll group exists: $EnrollGroup"
}

# Clone from "Workstation Authentication" (Client Auth base, request-supplied subject for non-person use)
$srcName = 'Workstation Authentication'
$src = Get-CertificateTemplate -Name $srcName -ErrorAction SilentlyContinue
if (-not $src) { Write-Fatal "Source template '$srcName' not found in AD." }
Write-OK "Source template: $srcName"

$exists = Get-CertificateTemplate -Name $TemplateName -ErrorAction SilentlyContinue
if ($exists) {
    Write-Skip "Template '$TemplateName' already exists - will re-tune."
} elseif ($PSCmdlet.ShouldProcess($TemplateName, "Clone from $srcName")) {
    if (-not $DryRun) {
        $cfgNC = (Get-ADRootDSE).configurationNamingContext
        $srcDn = "CN=$($src.CommonName),CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
        $srcObj = Get-ADObject -Identity $srcDn -Properties *
        $attrs = @{}
        $skipAttrs = @('distinguishedName','objectGUID','objectCategory','objectClass','cn','name','whenCreated','whenChanged','uSNCreated','uSNChanged','msPKI-Cert-Template-OID')
        foreach ($p in $srcObj.PSObject.Properties) {
            if ($skipAttrs -notcontains $p.Name -and $null -ne $p.Value -and $p.Name -notlike '*Object*') {
                $attrs[$p.Name] = $p.Value
            }
        }
        $attrs['displayName'] = $TemplateName
        New-ADObject -Name $TemplateName -Type 'pKICertificateTemplate' `
            -Path "CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC" `
            -OtherAttributes $attrs
        Write-OK "Cloned: $TemplateName"
    }
}

if ($DryRun) {
    Write-Warn 'DryRun mode - skipping property tuning and publishing'
    return
}

# Tune the template
$tpl = Get-CertificateTemplate -Name $TemplateName

# Short validity + renewal (days)
$tpl.Settings.ValidityPeriod = New-Object TimeSpan ($ValidityDays), 0, 0, 0
$tpl.Settings.RenewalPeriod  = New-Object TimeSpan ($RenewalDays),  0, 0, 0
Write-OK "Validity = $ValidityDays days, renewal window = $RenewalDays days"

# Subject supplied in request (non-person CN), not built from AD
$tpl.Settings.SubjectName = 'EnrolleeSuppliesSubject'
Write-OK 'Subject: supplied in request (workload CN)'

# EKU: Client + Server Auth for mutual TLS
$tpl.Settings.EnhancedKeyUsage.Clear()
$null = $tpl.Settings.EnhancedKeyUsage.Add('1.3.6.1.5.5.7.3.2')  # Client Authentication
$null = $tpl.Settings.EnhancedKeyUsage.Add('1.3.6.1.5.5.7.3.1')  # Server Authentication
Write-OK 'EKU: Client + Server Authentication (mTLS-ready)'

# Key + provider
$tpl.Settings.Cryptography.MinimalKeyLength = 2048
$tpl.Settings.Cryptography.KeyAlgorithm     = 'RSA'
$tpl.Settings.Cryptography.CSPList.Clear()
if ($UseTPM) {
    $null = $tpl.Settings.Cryptography.CSPList.Add('Microsoft Platform Crypto Provider')
    Write-OK 'Key Storage Provider: TPM'
} else {
    $null = $tpl.Settings.Cryptography.CSPList.Add('Microsoft Software Key Storage Provider')
    Write-OK 'Key Storage Provider: Software'
}

$tpl.Settings.RegistrationAuthority.SignatureCount = 0
$tpl.Commit()
Write-OK 'Template committed'

# Publish to CA
$published = Get-CATemplate -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $TemplateName -or $_.Name -eq $TemplateName }
if (-not $published) {
    Add-CATemplate -Name $TemplateName -Force
    Write-OK "Published $TemplateName to CA"
} else {
    Write-Skip "$TemplateName already published"
}

# Grant the enroll group Read + Enroll (NOT autoenroll - workloads enroll on demand)
$tpl = Get-CertificateTemplate -Name $TemplateName
$acl = $tpl | Get-CertificateTemplateAcl
$acl | Add-CertificateTemplateAcl -Identity $EnrollGroup `
        -AccessType Allow -AccessMask Read, Enroll | Set-CertificateTemplateAcl | Out-Null
Write-OK "Granted ${EnrollGroup}: Read + Enroll"

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    Template ready : $TemplateName ($ValidityDays-day, mTLS EKU)" -ForegroundColor White
Write-Host "    Enroll group   : $EnrollGroup" -ForegroundColor White
Write-Host '' -ForegroundColor White
Write-Host '    To enroll a workload cert (run as / for the service identity):' -ForegroundColor Yellow
Write-Host "      Get-Certificate -Template $TemplateName ``" -ForegroundColor Yellow
Write-Host '        -SubjectName "CN=svc-crm.lab.local" -CertStoreLocation Cert:\LocalMachine\My' -ForegroundColor Yellow
Write-Host '    Then: Enable-mTLS.ps1 to wire two services together with these certs.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
