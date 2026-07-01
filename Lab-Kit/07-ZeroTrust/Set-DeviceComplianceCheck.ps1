#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.2.3 - Evaluates local device posture (AV signature age, patch level,
    BitLocker, firewall) and publishes a COMPLIANT / NONCOMPLIANT verdict to an
    Active Directory computer attribute for Conditional Access to consume.

.DESCRIPTION
    Runs ON a domain-joined endpoint (workstation or server). Uses signals that
    ship in-box with Windows so the lab needs no third-party agent:

      - AV signature age     Get-MpComputerStatus (Microsoft Defender)
      - Real-time protection Get-MpComputerStatus
      - Patch recency        last installed hotfix / last successful update scan
      - BitLocker            Get-BitLockerVolume on the OS drive
      - Firewall             all three profiles enabled

    Each signal is scored against a threshold. The aggregate verdict and a JSON
    detail blob are written to the computer object's AD attribute (default
    extensionAttribute10) so Set-DeviceComplianceCheck output becomes a device-
    trust signal for Deploy-ConditionalAccess.ps1 (8.3.2) and the risk engine
    (8.3.3). A copy is cached under HKLM for local/offline reads.

    Designed to be run as SYSTEM on a schedule (the computer can write its own
    object's non-protected attributes). Run interactively as an admin to test.

.PARAMETER MaxSignatureAgeDays
    Fail if Defender signatures are older than this. Default 3.

.PARAMETER MaxPatchAgeDays
    Fail if no successful update / hotfix within this window. Default 35.

.PARAMETER AdAttribute
    AD attribute to publish the verdict to. Default 'extensionAttribute10'.

.PARAMETER SkipBitLocker
    Switch - do not require BitLocker (VMs / lab endpoints without TPM).

.PARAMETER DryRun
    Switch - evaluate and print, but do not write to AD or registry.

.EXAMPLE
    .\Set-DeviceComplianceCheck.ps1

.EXAMPLE
    .\Set-DeviceComplianceCheck.ps1 -SkipBitLocker -MaxSignatureAgeDays 7

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.2.3 - Device Trust
    Run on     : Each domain-joined endpoint (as SYSTEM on a schedule, ideally)
    Depends on : Microsoft Defender (or adapt the AV block to your product)
    NIST       : CM-7, CM-7(1), SI-3, SI-7
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [int]   $MaxSignatureAgeDays = 3,
    [int]   $MaxPatchAgeDays     = 35,
    [string]$AdAttribute         = 'extensionAttribute10',
    [switch]$SkipBitLocker,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Fail  { param([string]$msg) Write-Host "  [FAIL] $msg"   -ForegroundColor Red    }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8.2.3 - Device Compliance / Posture Check    |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

$results = [ordered]@{}
$fails   = @()

# -- AV signature age + real-time protection ----------------------------------
Write-Step 'Signal: Microsoft Defender'
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $sigAge = [math]::Round(((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays, 1)
    $results['AvSignatureAgeDays'] = $sigAge
    $results['RealTimeProtection'] = [bool]$mp.RealTimeProtectionEnabled

    if ($sigAge -le $MaxSignatureAgeDays) { Write-OK "Signatures $sigAge day(s) old (<= $MaxSignatureAgeDays)" }
    else { Write-Fail "Signatures $sigAge day(s) old (> $MaxSignatureAgeDays)"; $fails += 'AvSignatureStale' }

    if ($mp.RealTimeProtectionEnabled) { Write-OK 'Real-time protection ON' }
    else { Write-Fail 'Real-time protection OFF'; $fails += 'RealTimeProtectionOff' }
} catch {
    Write-Fail "Defender status unavailable: $($_.Exception.Message.Split([char]10)[0])"
    $results['AvSignatureAgeDays'] = $null
    $fails += 'AvUnavailable'
}
Write-Host ''

# -- Patch recency ------------------------------------------------------------
Write-Step 'Signal: Patch recency'
try {
    $lastHotfix = (Get-HotFix | Where-Object { $_.InstalledOn } |
                   Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
    if ($lastHotfix) {
        $patchAge = [math]::Round(((Get-Date) - $lastHotfix).TotalDays, 1)
        $results['LastPatchAgeDays'] = $patchAge
        if ($patchAge -le $MaxPatchAgeDays) { Write-OK "Last update $patchAge day(s) ago (<= $MaxPatchAgeDays)" }
        else { Write-Fail "Last update $patchAge day(s) ago (> $MaxPatchAgeDays)"; $fails += 'PatchStale' }
    } else {
        Write-Warn 'No dated hotfix found (image may use cumulative updates only)'
        $results['LastPatchAgeDays'] = $null
    }
} catch {
    Write-Warn "Hotfix query failed: $($_.Exception.Message.Split([char]10)[0])"
    $results['LastPatchAgeDays'] = $null
}
Write-Host ''

# -- BitLocker ----------------------------------------------------------------
Write-Step 'Signal: BitLocker (OS volume)'
if ($SkipBitLocker) {
    Write-Info 'Skipped (-SkipBitLocker)'
    $results['BitLockerOsVolume'] = 'Skipped'
} else {
    try {
        $osVol = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $results['BitLockerOsVolume'] = "$($osVol.ProtectionStatus)"
        if ($osVol.ProtectionStatus -eq 'On') { Write-OK "BitLocker ON ($($osVol.EncryptionPercentage)% encrypted)" }
        else { Write-Fail "BitLocker $($osVol.ProtectionStatus)"; $fails += 'BitLockerOff' }
    } catch {
        Write-Fail "BitLocker status unavailable: $($_.Exception.Message.Split([char]10)[0])"
        $results['BitLockerOsVolume'] = 'Unavailable'
        $fails += 'BitLockerUnavailable'
    }
}
Write-Host ''

# -- Firewall -----------------------------------------------------------------
Write-Step 'Signal: Windows Firewall (all profiles)'
try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
    $off = $profiles | Where-Object { -not $_.Enabled }
    $results['FirewallProfilesEnabled'] = (($profiles | Where-Object Enabled | Measure-Object).Count)
    if (-not $off) { Write-OK 'All firewall profiles enabled (Domain/Private/Public)' }
    else { Write-Fail "Firewall disabled on: $($off.Name -join ', ')"; $fails += 'FirewallOff' }
} catch {
    Write-Fail "Firewall query failed: $($_.Exception.Message.Split([char]10)[0])"
    $fails += 'FirewallUnavailable'
}
Write-Host ''

# -- Verdict ------------------------------------------------------------------
$verdict = if ($fails.Count -eq 0) { 'COMPLIANT' } else { 'NONCOMPLIANT' }
$payload = [ordered]@{
    Verdict     = $verdict
    Computer    = $env:COMPUTERNAME
    EvaluatedAt = (Get-Date).ToString('o')
    Failures    = $fails
    Signals     = $results
}
$json = $payload | ConvertTo-Json -Compress -Depth 4

Write-Step "Verdict: $verdict"
if ($verdict -eq 'COMPLIANT') { Write-OK 'Device meets posture baseline' }
else { Write-Fail "Failures: $($fails -join ', ')" }
Write-Host ''

# -- Publish: HKLM cache + AD attribute ---------------------------------------
if ($DryRun) {
    Write-Warn 'DryRun - not writing verdict to registry or AD'
    Write-Info $json
    return
}

# Local registry cache (readable offline / by other local logic)
$regPath = 'HKLM:\SOFTWARE\CAC-Program\ZeroTrust\DevicePosture'
if ($PSCmdlet.ShouldProcess($regPath, 'Write posture verdict to registry')) {
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name 'Verdict'     -Value $verdict
    Set-ItemProperty -Path $regPath -Name 'EvaluatedAt' -Value $payload.EvaluatedAt
    Set-ItemProperty -Path $regPath -Name 'Detail'      -Value $json
    Write-OK "Cached verdict at $regPath"
}

# AD computer attribute (the computer can write its own non-protected attrs as SYSTEM)
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $val = "$verdict|$($payload.EvaluatedAt)"
    if ($PSCmdlet.ShouldProcess("$env:COMPUTERNAME.$AdAttribute", "Set = $verdict")) {
        Set-ADComputer -Identity $env:COMPUTERNAME -Replace @{ $AdAttribute = $val } -ErrorAction Stop
        Write-OK "Published to AD: $AdAttribute = $val"
    }
} catch {
    Write-Warn "Could not write AD attribute (need ActiveDirectory module + self-write rights): $($_.Exception.Message.Split([char]10)[0])"
    Write-Info 'Run as SYSTEM on the endpoint, or delegate write on the chosen attribute to SELF.'
}

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    $env:COMPUTERNAME : $verdict" -ForegroundColor White
Write-Host '    Schedule this as SYSTEM (Task Scheduler) every few hours so the' -ForegroundColor Yellow
Write-Host "    device-trust signal in $AdAttribute stays fresh for Conditional Access." -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''

# Exit code reflects posture for schedulers/pipelines: 0 compliant, 1 not.
if ($verdict -ne 'COMPLIANT') { exit 1 }
