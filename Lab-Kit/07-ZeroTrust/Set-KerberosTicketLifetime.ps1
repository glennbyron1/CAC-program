#Requires -Version 5.1
#Requires -Modules GroupPolicy
<#
.SYNOPSIS
    Phase 8.3.1 - Shortens Kerberos TGT and TGS ticket lifetimes so the
    fleet re-evaluates trust more often. Continuous-evaluation cornerstone.

.DESCRIPTION
    Default AD ticket lifetimes (10h TGT, 10h TGS) are too long for ZT.
    A compromised session can survive 10 hours before AD re-checks anything.

    This script sets the Default Domain Policy KDC parameters to:
      Max user ticket lifetime           : 4 hours
      Max user ticket renewal            : 24 hours
      Max service ticket lifetime        : 10 minutes (was 600 = 10 hours)
      Max tolerance for clock skew       : 5 minutes (unchanged - tight default)

    Tradeoff: more KDC traffic, slightly higher DC load. In a 100-user
    lab/agency this is invisible. In a 10,000-user enterprise, plan to
    benchmark before rollout.

.PARAMETER GpoName
    GPO to edit. Default 'Default Domain Policy'. Pass a custom GPO if
    you'd rather not touch the default.

.PARAMETER TgtLifetimeHours
    Maximum user TGT lifetime. Default 4.

.PARAMETER TgtRenewalHours
    Maximum TGT renewal age. Default 24.

.PARAMETER TgsLifetimeMinutes
    Maximum service ticket lifetime. Default 10.

.PARAMETER DryRun
    Switch - preview without writing.

.EXAMPLE
    .\Set-KerberosTicketLifetime.ps1

.EXAMPLE
    .\Set-KerberosTicketLifetime.ps1 -TgtLifetimeHours 2 -TgsLifetimeMinutes 5

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.3.1 - Continuous & Conditional Access
    NIST       : AC-12, IA-5(13)
    Last Edit  : 2026-06-03
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GpoName             = 'Default Domain Policy',
    [int]   $TgtLifetimeHours    = 4,
    [int]   $TgtRenewalHours     = 24,
    [int]   $TgsLifetimeMinutes  = 10,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |     Phase 8.3.1 - Kerberos Ticket Lifetime           |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Import-Module GroupPolicy -ErrorAction Stop

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    Write-Fatal "GPO '$GpoName' not found."
}
Write-OK "Editing GPO: $GpoName"
Write-Host ''

# Kerberos settings live in Computer Configuration -> Policies -> Windows Settings ->
# Security Settings -> Account Policies -> Kerberos Policy
# We have to write the INF file directly - GPO PowerShell doesn't expose these.

$domain = (Get-ADDomain).DNSRoot
$gptPath = "\\$domain\SYSVOL\$domain\Policies\{$($gpo.Id)}\Machine\Microsoft\Windows NT\SecEdit"
if (-not (Test-Path $gptPath)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $gptPath -Force | Out-Null }
}
$infPath = Join-Path $gptPath 'GptTmpl.inf'

# Existing INF content (if any), strip Kerberos Policy section, re-append clean
$inf = ''
if (Test-Path $infPath) {
    $inf = Get-Content $infPath -Raw -Encoding Unicode
    # Drop existing [Kerberos Policy] block
    $inf = [regex]::Replace($inf, '(?s)\[Kerberos Policy\].*?(?=\[|\Z)', '')
}

# Build new INF
if (-not $inf) {
    $inf = "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n"
}
$inf += "[Kerberos Policy]`r`n"
$inf += "MaxTicketAge = $TgtLifetimeHours`r`n"
$inf += "MaxRenewAge = $($TgtRenewalHours / 24)`r`n"
$inf += "MaxServiceAge = $TgsLifetimeMinutes`r`n"
$inf += "MaxClockSkew = 5`r`n"
$inf += "TicketValidateClient = 1`r`n"

Write-Step 'Proposed Kerberos Policy:'
Write-Host "  MaxTicketAge   = $TgtLifetimeHours hours" -ForegroundColor Gray
Write-Host "  MaxRenewAge    = $TgtRenewalHours hours ($($TgtRenewalHours / 24) days)" -ForegroundColor Gray
Write-Host "  MaxServiceAge  = $TgsLifetimeMinutes minutes" -ForegroundColor Gray
Write-Host "  MaxClockSkew   = 5 minutes (default)" -ForegroundColor Gray
Write-Host ''

if ($DryRun) {
    Write-Warn 'DryRun - INF not written'
    return
}

if ($PSCmdlet.ShouldProcess($infPath, 'Write Kerberos policy INF')) {
    Set-Content -Path $infPath -Value $inf -Encoding Unicode
    Write-OK "Wrote $infPath"

    # Bump GPO so DCs pick it up
    Set-GPRegistryValue -Name $GpoName `
        -Key 'HKLM\Software\Policies\Microsoft\Windows\PhaseEight' `
        -ValueName 'KerberosPolicyApplied' -Type String -Value (Get-Date -Format 'o') | Out-Null

    Write-OK 'GPO version bumped'
}

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Kerberos ticket lifetimes shortened.' -ForegroundColor White
Write-Host '    On every DC: gpupdate /force' -ForegroundColor Yellow
Write-Host '    Verify on a workstation: klist purge; klist (after re-login)' -ForegroundColor Yellow
Write-Host '    Each ticket Renew Time / End Time should be within new bounds.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
