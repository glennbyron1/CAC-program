#Requires -Version 5.1
#Requires -Modules ActiveDirectory, GroupPolicy
<#
.SYNOPSIS
    Phase 8.1.2 - Builds least-privilege User Rights Assignment GPOs along
    tier boundaries. Tier 0 admins can only interactive-logon to Tier 0
    machines, Tier 1 to Tier 1, etc. Cross-tier logons are explicitly denied.

.DESCRIPTION
    Creates three GPOs:
      LP-Tier-0-UserRights
      LP-Tier-1-UserRights
      LP-Tier-2-UserRights

    Each GPO sets:
      - SeInteractiveLogonRight, SeRemoteInteractiveLogonRight, SeBatchLogonRight
        ALLOWED only for the tier's admin group + the local admin
      - SeDenyInteractiveLogonRight, SeDenyNetworkLogonRight,
        SeDenyRemoteInteractiveLogonRight, SeDenyBatchLogonRight
        DENIED for all other tiers' admin groups

    Links each GPO to its tier OU (created by Set-TieredAdminModel.ps1).

    Result: even if a Tier 2 admin credential is captured, it CANNOT be used
    to log into a Tier 0 machine. The DENY rights override any group
    membership inherited elsewhere.

.PARAMETER OUParent
    Distinguished name of the parent OU. Defaults to domain root.

.PARAMETER DryRun
    Switch - preview GPO settings without writing to AD.

.EXAMPLE
    .\Set-LeastPrivilegeGPO.ps1

.EXAMPLE
    .\Set-LeastPrivilegeGPO.ps1 -DryRun

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.1.2 - Authorization & Least Privilege
    Depends on : Set-TieredAdminModel.ps1 (creates the tier groups)
    NIST       : AC-3, AC-6, AC-6(7), AC-6(10)
    Last Edit  : 2026-06-03
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OUParent = '',
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
Write-Host '  |     Phase 8.1.2 - Least Privilege User Rights GPOs   |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy    -ErrorAction Stop

if (-not $OUParent) { $OUParent = (Get-ADDomain).DistinguishedName }
$adminOuDn = "OU=Admin,$OUParent"

# Verify tier model exists
foreach ($t in 0,1,2) {
    if (-not (Get-ADGroup -Filter "Name -eq 'Tier-$t-Admins'" -ErrorAction SilentlyContinue)) {
        Write-Fatal "Tier-$t-Admins group not found. Run Set-TieredAdminModel.ps1 first."
    }
}
Write-OK 'Tier groups verified'
Write-Host ''

# Settings INF template - sets User Rights Assignment via secedit-style file
# Allowed tier = its own admins + local admin. Denied tiers = the others.
$tierConfig = @(
    @{
        Tier      = 0
        Name      = 'LP-Tier-0-UserRights'
        OuPath    = "OU=Tier-0,$adminOuDn"
        Allow     = 'Tier-0-Admins'
        Deny      = @('Tier-1-Admins', 'Tier-2-Admins')
    }
    @{
        Tier      = 1
        Name      = 'LP-Tier-1-UserRights'
        OuPath    = "OU=Tier-1,$adminOuDn"
        Allow     = 'Tier-1-Admins'
        Deny      = @('Tier-0-Admins', 'Tier-2-Admins')
    }
    @{
        Tier      = 2
        Name      = 'LP-Tier-2-UserRights'
        OuPath    = "OU=Tier-2,$adminOuDn"
        Allow     = 'Tier-2-Admins'
        Deny      = @('Tier-0-Admins', 'Tier-1-Admins')
    }
)

# Rights to allow + rights to deny per cross-tier
$allowRights = @(
    'SeInteractiveLogonRight'
    'SeRemoteInteractiveLogonRight'
    'SeBatchLogonRight'
)
$denyRights = @(
    'SeDenyInteractiveLogonRight'
    'SeDenyNetworkLogonRight'
    'SeDenyRemoteInteractiveLogonRight'
    'SeDenyBatchLogonRight'
)

# Resolve group SIDs (User Rights Assignment uses SID strings in the INF)
function Get-GroupSidString {
    param([string]$Name)
    $g = Get-ADGroup -Identity $Name
    return "*$($g.SID.Value)"
}

foreach ($cfg in $tierConfig) {
    Write-Step "Configuring $($cfg.Name) -> $($cfg.OuPath)"

    # Create or reuse GPO
    $gpo = Get-GPO -Name $cfg.Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        if ($PSCmdlet.ShouldProcess($cfg.Name, 'New-GPO')) {
            if (-not $DryRun) {
                $gpo = New-GPO -Name $cfg.Name -Comment "Phase 8.1.2 - Tier $($cfg.Tier) user rights"
            }
            Write-OK "Created GPO: $($cfg.Name)"
        }
    } else {
        Write-Skip "GPO exists: $($cfg.Name)"
    }

    if ($DryRun) {
        Write-Host "       (DryRun) Would ALLOW $($cfg.Allow) -> $($allowRights -join ', ')" -ForegroundColor DarkGray
        foreach ($d in $cfg.Deny) {
            Write-Host "       (DryRun) Would DENY  $d -> $($denyRights -join ', ')" -ForegroundColor DarkGray
        }
        continue
    }

    # Build secedit INF for User Rights
    $allowSid = Get-GroupSidString -Name $cfg.Allow
    $localAdmin = '*S-1-5-32-544'   # Administrators (BUILTIN)
    $denyEntries = $cfg.Deny | ForEach-Object { Get-GroupSidString -Name $_ }
    $denyList = $denyEntries -join ','

    $inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
"@
    foreach ($r in $allowRights) {
        $inf += "`n$r = $allowSid,$localAdmin"
    }
    foreach ($r in $denyRights) {
        $inf += "`n$r = $denyList"
    }

    # Write INF to GPO sysvol
    $domain = (Get-ADDomain).DNSRoot
    $gptPath = "\\$domain\SYSVOL\$domain\Policies\{$($gpo.Id)}\Machine\Microsoft\Windows NT\SecEdit"
    if (-not (Test-Path $gptPath)) { New-Item -ItemType Directory -Path $gptPath -Force | Out-Null }
    $infPath = Join-Path $gptPath 'GptTmpl.inf'
    Set-Content -Path $infPath -Value $inf -Encoding Unicode
    Write-OK "User Rights INF written: $infPath"

    # Bump GPO version so clients re-apply
    Set-GPRegistryValue -Name $cfg.Name `
        -Key 'HKLM\Software\Policies\Microsoft\Windows\PhaseEight' `
        -ValueName 'LastApplied' -Type String -Value (Get-Date -Format 'o') | Out-Null

    # Link to tier OU if not already linked
    $existingLinks = (Get-GPInheritance -Target $cfg.OuPath -ErrorAction SilentlyContinue).GpoLinks
    $alreadyLinked = $existingLinks | Where-Object { $_.DisplayName -eq $cfg.Name }
    if ($alreadyLinked) {
        Write-Skip "Already linked to $($cfg.OuPath)"
    } else {
        if ($PSCmdlet.ShouldProcess($cfg.OuPath, "Link GPO $($cfg.Name)")) {
            New-GPLink -Name $cfg.Name -Target $cfg.OuPath -Enforced No -LinkEnabled Yes | Out-Null
            Write-OK "Linked to $($cfg.OuPath)"
        }
    }
    Write-Host ''
}

Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Tier user rights GPOs created and linked.' -ForegroundColor White
Write-Host '    On each tier-member machine, run: gpupdate /force' -ForegroundColor Yellow
Write-Host '    Then attempt a cross-tier logon - should be denied at the OS layer.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
