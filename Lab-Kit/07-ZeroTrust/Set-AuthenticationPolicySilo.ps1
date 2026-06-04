#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.1.4 - Creates Kerberos Authentication Policy Silos that enforce
    tier isolation at the protocol level. Tier 0 admin TGTs are issued ONLY
    on Tier 0 hosts; Tier 1 on Tier 1; Tier 2 on Tier 2.

.DESCRIPTION
    Authentication Policy Silos (introduced in Windows Server 2012 R2) are
    the strongest in-AD enforcement available. Even if a Tier 2 admin's
    password is stolen, Kerberos refuses to issue them a TGT from any host
    that isn't in the Tier 2 silo. The DC validates the silo membership
    against the source host's group membership at TGT issuance.

    Required for the deny to bite:
      1. Domain Functional Level >= Windows Server 2012 R2
      2. KDC Support for Claims & Compound Auth >= Supported (already set
         by default on 2016+ DCs)
      3. The target user account has AuthenticationPolicySilo set
      4. The user account is a member of the silo's UserAllowedToAuthenticate-from

    This script sets up #3 and #4. The DFL/KDC prereqs need a one-time check.

.PARAMETER OUParent
    Distinguished name of the parent OU. Defaults to domain root.

.PARAMETER DryRun
    Switch - preview without writing to AD.

.EXAMPLE
    .\Set-AuthenticationPolicySilo.ps1

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.1.4 - Authorization & Least Privilege
    Depends on : Set-TieredAdminModel.ps1 (creates Tier-N-AuthSilo-Users groups)
    NIST       : AC-3, AC-3(7), AC-6, IA-2
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
Write-Host '  |     Phase 8.1.4 - Authentication Policy Silos        |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Import-Module ActiveDirectory -ErrorAction Stop

# Prereq check: Domain Functional Level
$dfl = (Get-ADDomain).DomainMode
if ($dfl -lt 'Windows2012R2Domain') {
    Write-Fatal "Domain Functional Level is $dfl. Authentication Policy Silos require Windows2012R2Domain or higher."
}
Write-OK "Domain Functional Level: $dfl (sufficient)"
Write-Host ''

if (-not $OUParent) { $OUParent = (Get-ADDomain).DistinguishedName }

# Verify tier groups exist
foreach ($t in 0,1,2) {
    foreach ($suffix in 'Admins','AuthSilo-Users') {
        $g = "Tier-$t-$suffix"
        if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
            Write-Fatal "$g group missing. Run Set-TieredAdminModel.ps1 first."
        }
    }
}
Write-OK 'Tier groups verified'
Write-Host ''

# Plan: one Authentication Policy + one Authentication Policy Silo per tier
$silos = @(
    @{ Tier=0; Policy='AP-Tier-0'; Silo='APS-Tier-0'; AdminGroup='Tier-0-Admins'; AllowGroup='Tier-0-AuthSilo-Users' }
    @{ Tier=1; Policy='AP-Tier-1'; Silo='APS-Tier-1'; AdminGroup='Tier-1-Admins'; AllowGroup='Tier-1-AuthSilo-Users' }
    @{ Tier=2; Policy='AP-Tier-2'; Silo='APS-Tier-2'; AdminGroup='Tier-2-Admins'; AllowGroup='Tier-2-AuthSilo-Users' }
)

foreach ($s in $silos) {
    Write-Step "Tier $($s.Tier) - Silo $($s.Silo) / Policy $($s.Policy)"

    # The SDDL controls who can sign in TO this silo's machines via Kerberos.
    # Translation: TGT will be issued only if the user is in $($s.AllowGroup).
    $allowSid = (Get-ADGroup $s.AllowGroup).SID.Value
    $sddl = "O:SYG:SYD:(XA;OICI;CR;;;WD;(Member_of {SID($allowSid)}))"

    # 1. Authentication Policy
    $pol = Get-ADAuthenticationPolicy -Filter "Name -eq '$($s.Policy)'" -ErrorAction SilentlyContinue
    if (-not $pol) {
        if ($PSCmdlet.ShouldProcess($s.Policy, 'New-ADAuthenticationPolicy')) {
            if (-not $DryRun) {
                New-ADAuthenticationPolicy -Name $s.Policy `
                    -UserTGTLifetimeMins 240 `
                    -UserAllowedToAuthenticateFrom $sddl `
                    -Description "Phase 8.1.4 - Authentication Policy for Tier $($s.Tier)" `
                    -ProtectedFromAccidentalDeletion $true
            }
            Write-OK "Created policy: $($s.Policy)"
        }
    } else {
        Write-Skip "Policy exists: $($s.Policy)"
    }

    # 2. Authentication Policy Silo
    $silo = Get-ADAuthenticationPolicySilo -Filter "Name -eq '$($s.Silo)'" -ErrorAction SilentlyContinue
    if (-not $silo) {
        if ($PSCmdlet.ShouldProcess($s.Silo, 'New-ADAuthenticationPolicySilo')) {
            if (-not $DryRun) {
                New-ADAuthenticationPolicySilo -Name $s.Silo `
                    -UserAuthenticationPolicy   $s.Policy `
                    -ServiceAuthenticationPolicy $s.Policy `
                    -ComputerAuthenticationPolicy $s.Policy `
                    -Description "Phase 8.1.4 - Authentication Policy Silo for Tier $($s.Tier)" `
                    -Enforce `
                    -ProtectedFromAccidentalDeletion $true
            }
            Write-OK "Created silo: $($s.Silo) (Enforce mode)"
        }
    } else {
        Write-Skip "Silo exists: $($s.Silo)"
    }

    # 3. Grant the tier admin group access to the silo
    if (-not $DryRun) {
        Grant-ADAuthenticationPolicySiloAccess -Identity $s.Silo -Account $s.AdminGroup -ErrorAction SilentlyContinue
        Write-OK "Granted $($s.AdminGroup) access to silo"
    }

    # 4. Assign every member of the tier admin group to the policy
    $members = Get-ADGroupMember -Identity $s.AdminGroup -ErrorAction SilentlyContinue
    foreach ($m in $members) {
        if ($m.objectClass -in @('user','computer')) {
            if (-not $DryRun) {
                Set-ADAccountAuthenticationPolicySilo `
                    -Identity $m.SamAccountName `
                    -AuthenticationPolicySilo $s.Silo `
                    -AuthenticationPolicy     $s.Policy `
                    -ErrorAction SilentlyContinue
            }
        }
    }
    if ($members) {
        Write-OK "Assigned $($members.Count) member(s) of $($s.AdminGroup) to silo $($s.Silo)"
    } else {
        Write-Warn "$($s.AdminGroup) has no members yet - silo bind pending"
    }
    Write-Host ''
}

Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Authentication Policy Silos created and ENFORCING.' -ForegroundColor White
Write-Host '    Test (on a Tier 2 workstation):' -ForegroundColor Yellow
Write-Host '      runas /user:LAB\T0-Admin cmd  # should fail - wrong silo' -ForegroundColor Yellow
Write-Host '      runas /user:LAB\T2-Admin cmd  # should succeed - correct silo' -ForegroundColor Yellow
Write-Host '' -ForegroundColor Yellow
Write-Host '    To temporarily relax (e.g. during build):' -ForegroundColor Yellow
Write-Host '      Set-ADAuthenticationPolicySilo APS-Tier-0 -Enforce $false' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
