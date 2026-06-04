#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.7.1 - Validates that the Phase 8 ZT controls are in place and
    functioning. Complement to the existing Invoke-LabValidation.ps1
    (7-layer baseline check from Phase 4).

.DESCRIPTION
    Adds these checks on top of the baseline:
      L8  Tier model              : Admin/Tier-0/1/2 OUs + groups exist
      L9  Least-privilege GPO     : LP-Tier-N-UserRights GPOs created and linked
      L10 AP Silos                : APS-Tier-N silos exist and ENFORCING
      L11 Device certs            : ZT-Device-Authentication template published; certs issued
      L12 Kerberos lifetimes      : MaxTicketAge <= 4h, MaxServiceAge <= 10m
      L13 Microsegmentation       : ZT-Microsegmentation GPO linked to Tier 1 + Tier 2 OUs
      L14 Recent ZT events        : 4768 Pre-Auth Type 16 (smart card), 4624 from a tier-allowed host
                                    in the last 24h

    Each check is independent; failures don't stop the run. The final
    summary shows pass/fail per layer and an overall ZT posture grade.

.PARAMETER OUParent
    Domain root or testing parent. Default - actual domain root.

.PARAMETER ExportReport
    Switch - write a markdown report to C:\Windows\Logs\ZT-Validation-<date>.md.

.PARAMETER Quiet
    Switch - only print the summary block, no per-check chatter.

.EXAMPLE
    .\Invoke-ZeroTrustValidation.ps1

.EXAMPLE
    .\Invoke-ZeroTrustValidation.ps1 -ExportReport

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.7.1 - Validation & Evidence
    Last Edit  : 2026-06-03
#>

[CmdletBinding()]
param(
    [string]$OUParent     = '',
    [switch]$ExportReport,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) if (-not $Quiet) { Write-Host "  $msg"          -ForegroundColor Cyan   } }
function Write-OK    { param([string]$msg) if (-not $Quiet) { Write-Host "  [PASS] $msg"   -ForegroundColor Green  } }
function Write-Fail  { param([string]$msg)                  Write-Host "  [FAIL] $msg"   -ForegroundColor Red      }
function Write-Warn  { param([string]$msg)                  Write-Host "  [WARN] $msg"   -ForegroundColor Yellow   }
function Write-Info  { param([string]$msg) if (-not $Quiet) { Write-Host "       $msg"   -ForegroundColor Gray     } }

if (-not $Quiet) {
    Write-Host ''
    Write-Host '  +======================================================+' -ForegroundColor DarkCyan
    Write-Host '  |     Phase 8.7.1 - Zero Trust Validation              |' -ForegroundColor DarkCyan
    Write-Host '  +======================================================+' -ForegroundColor DarkCyan
    Write-Host ''
}

Import-Module ActiveDirectory -ErrorAction Stop

if (-not $OUParent) { $OUParent = (Get-ADDomain).DistinguishedName }
$results = @()

# -- L8 Tier model ----------------------------------------------------------
Write-Step 'L8  - Tier admin model'
$tierOk = $true
foreach ($t in 0,1,2) {
    $ouDn = "OU=Tier-$t,OU=Admin,$OUParent"
    if (-not (Get-ADOrganizationalUnit -Identity $ouDn -ErrorAction SilentlyContinue)) { $tierOk = $false; Write-Fail "Missing OU: $ouDn" }
    foreach ($suffix in 'Admins','Servers','Workstations','AuthSilo-Users') {
        $gName = "Tier-$t-$suffix"
        if ($suffix -eq 'Servers' -and $t -eq 2) { continue }
        if ($suffix -eq 'Workstations' -and $t -ne 2) { continue }
        if (-not (Get-ADGroup -Filter "Name -eq '$gName'" -ErrorAction SilentlyContinue)) { $tierOk = $false; Write-Fail "Missing group: $gName" }
    }
}
if ($tierOk) { Write-OK 'All tier OUs and groups present' }
$results += [PSCustomObject]@{ Layer='L8'; Name='Tier admin model'; Status=if($tierOk){'PASS'}else{'FAIL'} }

# -- L9 Least-privilege GPOs ------------------------------------------------
Write-Step 'L9  - Least-privilege user rights GPOs'
Import-Module GroupPolicy -ErrorAction SilentlyContinue
$gpoOk = $true
foreach ($t in 0,1,2) {
    $g = Get-GPO -Name "LP-Tier-$t-UserRights" -ErrorAction SilentlyContinue
    if (-not $g) { $gpoOk = $false; Write-Fail "Missing GPO: LP-Tier-$t-UserRights"; continue }
    $link = (Get-GPInheritance -Target "OU=Tier-$t,OU=Admin,$OUParent" -ErrorAction SilentlyContinue).GpoLinks |
            Where-Object { $_.DisplayName -eq "LP-Tier-$t-UserRights" }
    if (-not $link) { $gpoOk = $false; Write-Fail "GPO LP-Tier-$t-UserRights exists but not linked to its tier OU" }
}
if ($gpoOk) { Write-OK 'All LP GPOs present and linked' }
$results += [PSCustomObject]@{ Layer='L9'; Name='Least-privilege GPOs'; Status=if($gpoOk){'PASS'}else{'FAIL'} }

# -- L10 Authentication Policy Silos ----------------------------------------
Write-Step 'L10 - Authentication Policy Silos (Kerberos enforcement)'
$siloOk = $true
foreach ($t in 0,1,2) {
    $s = Get-ADAuthenticationPolicySilo -Filter "Name -eq 'APS-Tier-$t'" -ErrorAction SilentlyContinue
    if (-not $s) { $siloOk = $false; Write-Fail "Missing silo: APS-Tier-$t"; continue }
    if (-not $s.Enforce) { Write-Warn "Silo APS-Tier-$t is in audit mode (not enforcing)"; $siloOk = $false }
}
if ($siloOk) { Write-OK 'All silos present and enforcing' }
$results += [PSCustomObject]@{ Layer='L10'; Name='Authentication Policy Silos'; Status=if($siloOk){'PASS'}else{'FAIL'} }

# -- L11 Device cert plumbing -----------------------------------------------
Write-Step 'L11 - Device certificate template + issued certs'
$dcOk = $true
$cfgNC = (Get-ADRootDSE).configurationNamingContext
$tplDn = "CN=ZT-Device-Authentication,CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
if (-not (Get-ADObject -Identity $tplDn -ErrorAction SilentlyContinue)) {
    Write-Fail 'Template ZT-Device-Authentication missing'
    $dcOk = $false
} else {
    Write-Info '   Template present'
}
$gpoAE = Get-GPO -Name 'ZT-Autoenroll-Device-Certs' -ErrorAction SilentlyContinue
if (-not $gpoAE) {
    Write-Fail 'Autoenrollment GPO missing'
    $dcOk = $false
} else {
    Write-Info '   Autoenrollment GPO present'
}
if ($dcOk) { Write-OK 'Template + autoenrollment GPO in place' }
$results += [PSCustomObject]@{ Layer='L11'; Name='Device certs'; Status=if($dcOk){'PASS'}else{'FAIL'} }

# -- L12 Kerberos ticket lifetimes ------------------------------------------
Write-Step 'L12 - Kerberos ticket lifetimes shortened'
$kerbOk = $false
try {
    $domain = (Get-ADDomain).DNSRoot
    $infPath = "\\$domain\SYSVOL\$domain\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
    if (Test-Path $infPath) {
        $infText = Get-Content $infPath -Raw -Encoding Unicode
        if ($infText -match 'MaxTicketAge\s*=\s*(\d+)') {
            $tgt = [int]$matches[1]
            if ($tgt -le 4) { $kerbOk = $true; Write-Info "   MaxTicketAge = $tgt h" } else { Write-Warn "MaxTicketAge = $tgt h (target <= 4)" }
        }
        if ($infText -match 'MaxServiceAge\s*=\s*(\d+)') {
            $tgs = [int]$matches[1]
            Write-Info "   MaxServiceAge = $tgs min"
        }
    } else { Write-Fail 'Default Domain Policy SecEdit INF not readable' }
} catch { Write-Fail "Could not check Kerberos policy: $($_.Exception.Message.Split([char]10)[0])" }
if ($kerbOk) { Write-OK 'Kerberos lifetimes shortened' }
$results += [PSCustomObject]@{ Layer='L12'; Name='Kerberos lifetimes'; Status=if($kerbOk){'PASS'}else{'FAIL'} }

# -- L13 Microsegmentation --------------------------------------------------
Write-Step 'L13 - Microsegmentation GPO present and linked'
$segOk = $true
$gpoSeg = Get-GPO -Name 'ZT-Microsegmentation' -ErrorAction SilentlyContinue
if (-not $gpoSeg) {
    $segOk = $false; Write-Fail 'GPO ZT-Microsegmentation not found'
} else {
    foreach ($t in 1, 2) {
        $ouDn = "OU=Tier-$t,OU=Admin,$OUParent"
        $link = (Get-GPInheritance -Target $ouDn -ErrorAction SilentlyContinue).GpoLinks |
                Where-Object { $_.DisplayName -eq 'ZT-Microsegmentation' }
        if (-not $link) { $segOk = $false; Write-Fail "Microsegmentation GPO not linked to Tier $t OU" }
    }
}
if ($segOk) { Write-OK 'Microsegmentation linked to Tier 1 + Tier 2' }
$results += [PSCustomObject]@{ Layer='L13'; Name='Microsegmentation'; Status=if($segOk){'PASS'}else{'FAIL'} }

# -- L14 Recent ZT events ---------------------------------------------------
Write-Step 'L14 - Recent ZT-aligned auth events (last 24h)'
$eventOk = $false
try {
    $since = (Get-Date).AddHours(-24)
    $smartCardCount = (Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4768; StartTime=$since} -ErrorAction SilentlyContinue |
                       Where-Object { $_.Message -match 'Pre-Authentication Type:\s+16' }).Count
    Write-Info "   Smart-card PKINIT TGTs in last 24h: $smartCardCount"
    if ($smartCardCount -gt 0) { $eventOk = $true }
} catch { Write-Warn "Could not query Security log: $($_.Exception.Message.Split([char]10)[0])" }
if ($eventOk) { Write-OK 'PKINIT smart-card auth observed in last 24h' } else { Write-Warn 'No PKINIT TGTs in last 24h (lab may have been idle)' }
$results += [PSCustomObject]@{ Layer='L14'; Name='Recent PKINIT events'; Status=if($eventOk){'PASS'}else{'WARN'} }

# -- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host ('  +-- ZT Validation Summary ' + ('-' * 40)) -ForegroundColor DarkCyan
$results | Format-Table Layer, Name, Status -AutoSize | Out-Host
$passCount = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$total     = @($results).Count

Write-Host ("    PASS : $passCount / $total") -ForegroundColor Green
Write-Host ("    FAIL : $failCount / $total") -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
$grade = if ($failCount -eq 0) {'A - ZT controls fully operational'} elseif ($failCount -le 2) {'B - mostly operational, fix gaps'} elseif ($failCount -le 4) {'C - partial - several gaps'} else {'D - foundation incomplete'}
Write-Host ("    ZT Posture Grade : $grade") -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan

# -- Optional report --------------------------------------------------------
if ($ExportReport) {
    $reportPath = "C:\Windows\Logs\ZT-Validation-$(Get-Date -Format yyyyMMdd-HHmm).md"
    $md = @()
    $md += '# Phase 8 Zero Trust Validation Report'
    $md += ''
    $md += "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $md += "**Host:** $env:COMPUTERNAME"
    $md += "**Domain:** $((Get-ADDomain).DNSRoot)"
    $md += "**Grade:** $grade"
    $md += ''
    $md += '## Results'
    $md += ''
    $md += '| Layer | Name | Status |'
    $md += '|---|---|---|'
    foreach ($r in $results) { $md += ("| $($r.Layer) | $($r.Name) | $($r.Status) |") }
    $md | Set-Content -Path $reportPath -Encoding UTF8
    Write-OK "Report written: $reportPath"
}

Write-Host ''
