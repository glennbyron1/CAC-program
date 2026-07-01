#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.4.2 - Audits user-based service accounts and converts them to Group
    Managed Service Accounts (gMSA), removing stored/static passwords.

.DESCRIPTION
    Static service-account passwords are a top lateral-movement vector (Kerberoast,
    credential theft, never-expiring secrets). This script:

      1. Ensures the KDS root key exists (creates it for the lab with immediate
         effect; production must wait 10 hours for AD replication).
      2. Audits the directory for "risky" service identities - enabled USER
         accounts that carry a servicePrincipalName (i.e. something logs on as
         them) and are not already gMSAs.
      3. For each discovered account (or for -Names you pass), creates a matching
         gMSA whose password AD rotates automatically every 30 days, and grants
         the host(s) in -AllowedHosts permission to retrieve it.

    The script does NOT delete the old user account or rebind the live service -
    that is a change-controlled cutover you do per service:
        sc.exe config <svc> obj= lab\svc-crm$ password=
        (gMSA logon uses the trailing $ and an empty password)

    Re-running is safe; existing gMSAs are reused.

.PARAMETER Names
    Explicit list of service short-names to create as gMSAs (e.g. svc-crm,
    svc-backup). If omitted, the script audits AD and proposes candidates.

.PARAMETER AllowedHosts
    Computer accounts (sAMAccountName, with or without trailing $) permitted to
    use the gMSAs. Default: the current computer.

.PARAMETER OUPath
    OU to create the gMSAs in. Default: Managed Service Accounts container.

.PARAMETER AuditOnly
    Switch - only report risky accounts; create nothing.

.PARAMETER DryRun
    Switch - preview writes without applying.

.EXAMPLE
    # Audit what should be converted
    .\Set-ServiceAccountHardening.ps1 -AuditOnly

.EXAMPLE
    # Create gMSAs for two services, usable by the app servers
    .\Set-ServiceAccountHardening.ps1 -Names svc-crm,svc-backup -AllowedHosts APP01,APP02

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.4.2 - Workload / NPI (optional)
    Run on     : Lab-DC01
    Depends on : KDS root key (created here if missing)
    NIST       : IA-5, IA-5(2), AC-2, AC-2(7)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Names        = @(),
    [string[]]$AllowedHosts = @(),
    [string]  $OUPath       = '',
    [switch]  $AuditOnly,
    [switch]  $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Skip  { param([string]$msg) Write-Host "  [SKIP] $msg"   -ForegroundColor DarkGray }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8.4.2 - Service Account Hardening (gMSA)     |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Fatal 'ActiveDirectory module not available. Run on Lab-DC01 with RSAT installed.'
}
Import-Module ActiveDirectory -ErrorAction Stop

$domain = Get-ADDomain
if (-not $OUPath) { $OUPath = "CN=Managed Service Accounts,$($domain.DistinguishedName)" }
if ($AllowedHosts.Count -eq 0) { $AllowedHosts = @($env:COMPUTERNAME) }
# normalise host names to sAMAccountName form (trailing $)
$hostSam = $AllowedHosts | ForEach-Object { if ($_ -like '*$') { $_ } else { "$_`$" } }

# -- Step 1: KDS root key -----------------------------------------------------
Write-Step 'Phase 1 - KDS root key (gMSA password generation)'
$kds = Get-KdsRootKey -ErrorAction SilentlyContinue
if ($kds) {
    Write-Skip "KDS root key already present (effective $($kds.EffectiveTime))"
} elseif ($PSCmdlet.ShouldProcess('KDS root key', 'Create (effective immediately - lab)')) {
    if (-not $DryRun) {
        # -10h backdates so it is usable now in a single-DC lab. Production: omit and wait 10h.
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) | Out-Null
    }
    Write-OK 'Created KDS root key (backdated for immediate lab use)'
    Write-Warn 'Production note: in a multi-DC forest, omit the backdate and wait 10h for replication.'
}
Write-Host ''

# -- Step 2: audit risky service accounts -------------------------------------
Write-Step 'Phase 2 - Audit user accounts acting as services (SPN holders)'
$risky = Get-ADUser -Filter { Enabled -eq $true -and ServicePrincipalName -like '*' } `
            -Properties ServicePrincipalName, PasswordLastSet, PasswordNeverExpires, servicePrincipalName |
         Select-Object SamAccountName, PasswordLastSet, PasswordNeverExpires,
            @{n='SPNs';e={ ($_.ServicePrincipalName | Measure-Object).Count }}

if ($risky) {
    Write-Warn "Found $(($risky | Measure-Object).Count) user-based service identit(ies):"
    $risky | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
} else {
    Write-OK 'No user accounts with SPNs found (krbtgt and computer accounts excluded).'
}
Write-Host ''

if ($AuditOnly) {
    Write-Host ('  +-- Audit complete ' + ('-' * 43)) -ForegroundColor DarkCyan
    Write-Host '    Re-run with -Names <svc1>,<svc2> -AllowedHosts <host> to create gMSAs.' -ForegroundColor Yellow
    Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
    Write-Host ''
    return
}

# -- Step 3: create gMSAs -----------------------------------------------------
if ($Names.Count -eq 0) {
    Write-Warn 'No -Names supplied. Pass the service short-names to convert, e.g.:'
    Write-Info  '  .\Set-ServiceAccountHardening.ps1 -Names svc-crm,svc-backup -AllowedHosts APP01'
    Write-Host ''
    return
}

Write-Step 'Phase 3 - Create gMSAs'
Write-Info  "Allowed hosts: $($hostSam -join ', ')"
Write-Host ''

foreach ($n in $Names) {
    $gmsaName = $n.TrimEnd('$')
    if ($gmsaName.Length -gt 15) {
        Write-Warn "$gmsaName exceeds 15 chars (sAMAccountName limit for accounts). Shorten it."
        continue
    }

    $existing = $null
    try { $existing = Get-ADServiceAccount -Identity $gmsaName -ErrorAction SilentlyContinue } catch {}
    if ($existing) {
        Write-Skip "gMSA exists: $gmsaName"
    } elseif ($PSCmdlet.ShouldProcess($gmsaName, 'Create gMSA')) {
        if (-not $DryRun) {
            New-ADServiceAccount -Name $gmsaName `
                -DNSHostName "$gmsaName.$($domain.DNSRoot)" `
                -ManagedPasswordIntervalInDays 30 `
                -PrincipalsAllowedToRetrieveManagedPassword $hostSam `
                -Path $OUPath `
                -Enabled $true `
                -Description 'Phase 8.4.2 - gMSA replacing a static-password service account'
        }
        Write-OK "Created gMSA: $gmsaName (30-day auto-rotation)"
    }
}
Write-Host ''

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    gMSAs created. Per-service cutover (change-controlled):' -ForegroundColor White
Write-Host '      On the service host:' -ForegroundColor Yellow
Write-Host '        Install-ADServiceAccount <gmsa>          # caches the gMSA locally' -ForegroundColor Yellow
Write-Host '        Test-ADServiceAccount    <gmsa>          # expect: True' -ForegroundColor Yellow
Write-Host '      Repoint the service to the gMSA (empty password, trailing $):' -ForegroundColor Yellow
Write-Host '        sc.exe config <svc> obj= lab\<gmsa>$ password=' -ForegroundColor Yellow
Write-Host '      Then disable + retire the old user account once verified.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
