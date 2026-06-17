#Requires -Version 5.1
<#
.SYNOPSIS
    Create a new lab AD user account and immediately begin smart card enrollment (RA phase).

.DESCRIPTION
    Creates a standard Active Directory user account and then invokes
    New-TokenEnrollment.ps1 -Mode RA for the same account so the Registration
    Authority can complete identity verification and authorize token issuance
    in a single workflow.

    Document ID : SCRIPT-ICAM-012
    Framework   : NIST SP 800-53 IA-4, IA-5 | FIPS 201-3

.PARAMETER FirstName
    Enrollee's first name.

.PARAMETER LastName
    Enrollee's last name.

.PARAMETER UPN
    Full User Principal Name (e.g., jsmith@lab.local). Derived from FirstName/LastName
    and Domain if omitted.

.PARAMETER Domain
    UPN suffix / domain (e.g., lab.local). Used when UPN is not supplied explicitly.

.PARAMETER OrgUnit
    Distinguished name of the target OU (e.g., "OU=Users,DC=lab,DC=local").
    Prompted at runtime if not supplied.

.PARAMETER DomainController
    Domain controller to create the account on. Auto-detected if omitted.

.PARAMETER LogPath
    Audit log path passed through to New-TokenEnrollment.ps1.
    Default: C:\Windows\Logs\TokenEnrollment.log

.EXAMPLE
    .\New-LabUser.ps1 -FirstName Jane -LastName Doe -Domain lab.local

.EXAMPLE
    .\New-LabUser.ps1 -FirstName Jane -LastName Doe -UPN jdoe@lab.local `
        -OrgUnit "OU=Users,DC=lab,DC=local"

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    After this script completes the RA phase, a DIFFERENT administrator must log in
    and run:  .\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName <UPN>
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$FirstName,

    [Parameter(Mandatory)]
    [string]$LastName,

    [Parameter()]
    [string]$UPN = "",

    [Parameter()]
    [string]$Domain = "lab.local",

    [Parameter()]
    [string]$OrgUnit = "",

    [Parameter()]
    [string]$DomainController = "",

    [Parameter()]
    [string]$LogPath = "C:\Windows\Logs\TokenEnrollment.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$width = 72
Write-Host ""
Write-Host ("=" * $width) -ForegroundColor DarkCyan
Write-Host "  NEW LAB USER + CAC ENROLLMENT - SCRIPT-ICAM-012" -ForegroundColor Cyan
Write-Host "  Author: Glenn Byron  |  NIST SP 800-53 IA-4, IA-5" -ForegroundColor Cyan
Write-Host ("=" * $width) -ForegroundColor DarkCyan
Write-Host ""

# ---------------------------------------------------------------------------
# Prerequisite check
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "  [FAIL] ActiveDirectory PowerShell module is not installed." -ForegroundColor Red
    Write-Host "  Install RSAT: Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'" -ForegroundColor DarkGray
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

$enrollScript = Join-Path $PSScriptRoot "New-TokenEnrollment.ps1"
if (-not (Test-Path $enrollScript)) {
    Write-Host "  [FAIL] Cannot find New-TokenEnrollment.ps1 in $PSScriptRoot" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Derive account values
# ---------------------------------------------------------------------------
$samAccountName = ($FirstName.Substring(0,1) + $LastName).ToLower() -replace '[^a-z0-9]', ''
if ($samAccountName.Length -gt 20) { $samAccountName = $samAccountName.Substring(0,20) }

if (-not $UPN) {
    $UPN = "$samAccountName@$Domain"
}

$displayName = "$FirstName $LastName"

# ---------------------------------------------------------------------------
# Prompt for OU if not supplied, then resolve bare names to full DN
# ---------------------------------------------------------------------------
function Resolve-OrgUnit {
    param([string]$OUName)

    # Already a valid DN (contains = and ,) - use as-is
    if ($OUName -match '=' -and $OUName -match ',') { return $OUName }

    # Bare name - search AD for a matching OU or built-in container
    Write-Host "  [*] '$OUName' looks like a name, not a DN. Searching AD..." -ForegroundColor White

    $searchParams = @{ ErrorAction = 'SilentlyContinue' }
    if ($DomainController) { $searchParams['Server'] = $DomainController }

    # Try OUs first
    $candidates = @(Get-ADOrganizationalUnit -Filter { Name -eq $OUName } @searchParams |
                    Select-Object -ExpandProperty DistinguishedName)

    # Fall back to well-known containers (CN=Users, CN=Computers, etc.)
    # Exclude policy sub-containers under CN=Policies or CN=System
    if ($candidates.Count -eq 0) {
        $candidates = @(Get-ADObject -Filter { Name -eq $OUName -and ObjectClass -eq 'container' } @searchParams |
                        Where-Object { $_.DistinguishedName -notmatch 'CN=Policies|CN=System' } |
                        Select-Object -ExpandProperty DistinguishedName)
    }

    if ($candidates.Count -eq 0) {
        Write-Host "  [FAIL] No OU or container named '$OUName' found in AD." -ForegroundColor Red
        Write-Host "         Supply the full DN, e.g.: OU=Users,DC=lab,DC=local" -ForegroundColor DarkGray
        exit 1
    }

    if ($candidates.Count -eq 1) {
        Write-Host "  [OK] Resolved to: $($candidates[0])" -ForegroundColor Green
        return $candidates[0]
    }

    # Multiple matches - let the user pick
    Write-Host "  Multiple matches found:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host "    [$($i+1)] $($candidates[$i])" }
    do {
        $pick = Read-Host "  Select [1-$($candidates.Count)]"
    } while ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $candidates.Count)
    return $candidates[[int]$pick - 1]
}

if (-not $OrgUnit) {
    $knownOUs = [ordered]@{
        "1" = @{ Label = "SmartCard-Pilot  (OU=SmartCard-Pilot,DC=lab,DC=local)"; DN = "OU=SmartCard-Pilot,DC=lab,DC=local" }
        "2" = @{ Label = "Users            (CN=Users,DC=lab,DC=local)";            DN = "CN=Users,DC=lab,DC=local" }
        "3" = @{ Label = "Admin            (OU=Admin,DC=lab,DC=local)";            DN = "OU=Admin,DC=lab,DC=local" }
        "4" = @{ Label = "Other - type a name or full DN";                          DN = $null }
    }

    Write-Host "  Select target OU:" -ForegroundColor White
    Write-Host ""
    foreach ($k in $knownOUs.Keys) {
        Write-Host "    [$k] $($knownOUs[$k].Label)"
    }
    Write-Host ""
    do { $pick = Read-Host "  Choice [1-$($knownOUs.Count)]" } while ($pick -notin $knownOUs.Keys)

    if ($knownOUs[$pick].DN) {
        $OrgUnit = $knownOUs[$pick].DN
        Write-Host "  [OK] Using: $OrgUnit" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  You can type just the name (e.g. SmartCard-Pilot) or the full DN." -ForegroundColor DarkGray
        $OrgUnit = Read-Host "  Target OU"
        if (-not $OrgUnit) {
            Write-Host "  [FAIL] OU is required." -ForegroundColor Red
            exit 1
        }
    }
}

$OrgUnit = Resolve-OrgUnit -OUName $OrgUnit

# ---------------------------------------------------------------------------
# Confirm before creating
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Account to be created:" -ForegroundColor Cyan
Write-Host "    Display Name   : $displayName"
Write-Host "    SAM Account    : $samAccountName"
Write-Host "    UPN            : $UPN"
Write-Host "    Target OU      : $OrgUnit"
if ($DomainController) { Write-Host "    DC             : $DomainController" }
Write-Host ""

$ans = Read-Host "  Proceed? [Y/N]"
if ($ans -notin @('Y','y')) {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Check for duplicate
# ---------------------------------------------------------------------------
$existing = $null
try {
    $filter = "UserPrincipalName -eq '$UPN'"
    $existing = if ($DomainController) {
        Get-ADUser -Filter $filter -Server $DomainController -ErrorAction SilentlyContinue
    } else {
        Get-ADUser -Filter $filter -ErrorAction SilentlyContinue
    }
} catch { }

if ($existing) {
    Write-Host ""
    Write-Host "  [!!] An account with UPN '$UPN' already exists." -ForegroundColor Yellow
    Write-Host "       SAM: $($existing.SamAccountName)  |  DN: $($existing.DistinguishedName)" -ForegroundColor DarkGray
    $skip = Read-Host "  Skip account creation and go straight to RA enrollment? [Y/N]"
    if ($skip -notin @('Y','y')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    # ---------------------------------------------------------------------------
    # Create the account
    # ---------------------------------------------------------------------------
    Write-Host ""
    Write-Host "  [*] Creating AD account..." -ForegroundColor White

    $newUserParams = @{
        Name              = $displayName
        GivenName         = $FirstName
        Surname           = $LastName
        DisplayName       = $displayName
        SamAccountName    = $samAccountName
        UserPrincipalName = $UPN
        Path              = $OrgUnit
        AccountPassword   = (ConvertTo-SecureString "ChangeMe1!" -AsPlainText -Force)
        ChangePasswordAtLogon = $true
        Enabled           = $true
    }

    if ($DomainController) { $newUserParams['Server'] = $DomainController }

    if ($PSCmdlet.ShouldProcess($UPN, "Create AD user")) {
        New-ADUser @newUserParams
        Write-Host "  [OK] Account created: $UPN" -ForegroundColor Green
        Write-Host "       Temporary password: ChangeMe1!  (enrollee must change at next logon)" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Hand off to RA phase
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * $width) -ForegroundColor Yellow
Write-Host "  HANDING OFF TO TOKEN ENROLLMENT - RA PHASE" -ForegroundColor Yellow
Write-Host ("=" * $width) -ForegroundColor Yellow
Write-Host ""

$raParams = @{
    Mode                = 'RA'
    UserPrincipalName   = $UPN
    LogPath             = $LogPath
}
if ($DomainController) { $raParams['DomainController'] = $DomainController }

& $enrollScript @raParams
