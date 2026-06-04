#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.1 - Builds the Tier 0 / Tier 1 / Tier 2 administrative model in
    Active Directory: OU structure, admin groups, default-deny cross-tier
    isolation. Aligned to Microsoft's "Securing Privileged Access" guidance.

.DESCRIPTION
    Establishes the AD foundation that every other Phase 8 control depends on:
    - Authentication Policy Silos (8.1.4) reference these tier groups
    - Device cert templates (8.2) scope by tier
    - Conditional Access policies (8.3) gate by tier membership
    - Microsegmentation (8.5) firewalls between tier subnets

    Tier model:
      Tier 0  - Identity infrastructure (DCs, ADCS, ADFS, AAD Connect, PAM).
                Highest trust. Tier 0 admins can compromise the entire forest.
      Tier 1  - Server admins (file, app, database, web). Can compromise the
                workloads they administer but not the identity plane.
      Tier 2  - Workstation admins (helpdesk, desktop support). Can compromise
                end-user devices but not servers or DCs.

    Cross-tier rule (enforced later by Authentication Policy Silos in 8.1.4):
      Higher-tier credentials are NEVER used to log into lower-tier assets.
      Lower-tier admins can NEVER log into higher-tier assets.

.PARAMETER OUParent
    Distinguished name of the parent OU where the Admin/ structure is created.
    Defaults to the domain root (DC=lab,DC=local style).

.PARAMETER DryRun
    Switch - show what would be created without writing to AD.

.PARAMETER CreateSeedAccounts
    Switch - also create one example admin account per tier (T0-Admin,
    T1-Admin, T2-Admin) with random passwords printed once. Off by default
    so this script is safe to re-run.

.EXAMPLE
    # Default - create OU + group structure on the running domain
    .\Set-TieredAdminModel.ps1

.EXAMPLE
    # Preview the plan without touching AD
    .\Set-TieredAdminModel.ps1 -DryRun

.EXAMPLE
    # Also seed one example admin account per tier
    .\Set-TieredAdminModel.ps1 -CreateSeedAccounts

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.1 - Authorization & Least Privilege
    Reference  : Microsoft "Securing Privileged Access" tiered model
                 NIST SP 800-53 AC-2, AC-3, AC-5, AC-6
    Last Edit  : 2026-06-03
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OUParent = '',
    [switch]$DryRun,
    [switch]$CreateSeedAccounts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Skip  { param([string]$msg) Write-Host "  [SKIP] $msg"   -ForegroundColor DarkGray }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

function New-RandomPassword {
    # 20 chars: upper, lower, digit, symbol. Safe for AD complexity requirements.
    $upper  = [char[]](65..90)
    $lower  = [char[]](97..122)
    $digit  = [char[]](48..57)
    $symbol = [char[]]'!@#$%^&*()_-+='
    $all    = $upper + $lower + $digit + $symbol
    $pw     = -join (1..20 | ForEach-Object { $all | Get-Random })
    return $pw
}

# -- Banner -------------------------------------------------------------------
Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |     Phase 8.1 - Tiered Admin Model (Tier 0/1/2)      |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# -- Validate ActiveDirectory module ------------------------------------------
if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Fatal 'ActiveDirectory module not available. Run on Lab-DC01 with RSAT installed.'
}
Import-Module ActiveDirectory -ErrorAction Stop

# -- Resolve OU parent --------------------------------------------------------
if (-not $OUParent) {
    $OUParent = (Get-ADDomain).DistinguishedName
}
Write-Step "Domain root  : $OUParent"
Write-Step "Mode         : $(if ($DryRun) { 'DRY RUN (no writes)' } else { 'APPLY' })"
Write-Step "Seed accounts: $(if ($CreateSeedAccounts) { 'YES' } else { 'no' })"
Write-Host ''

# -- Define the model ---------------------------------------------------------
# Tier OU layout under OU=Admin
$tierPlan = @(
    @{
        Tier     = 0
        OU       = 'Tier-0'
        Comment  = 'Identity infrastructure - DCs, ADCS, ADFS, AAD Connect, PAM. NEVER touches workstations or member servers.'
        Groups   = @(
            @{ Name='Tier-0-Admins';        Scope='Global';     Desc='Tier 0 administrative principals (domain forest admin tier)' }
            @{ Name='Tier-0-Servers';       Scope='Global';     Desc='Tier 0 server computer accounts (DCs, CAs, ADFS)' }
            @{ Name='Tier-0-AuthSilo-Users';Scope='Universal';  Desc='Members allowed to authenticate INTO Tier 0 resources via Authentication Policy Silo' }
        )
    }
    @{
        Tier     = 1
        OU       = 'Tier-1'
        Comment  = 'Server admins (file, app, database, web). Cannot log into DCs. Cannot use Tier 0 credentials.'
        Groups   = @(
            @{ Name='Tier-1-Admins';        Scope='Global';     Desc='Tier 1 server administrators (member-server admin tier)' }
            @{ Name='Tier-1-Servers';       Scope='Global';     Desc='Tier 1 server computer accounts (file/app/db/web)' }
            @{ Name='Tier-1-AuthSilo-Users';Scope='Universal';  Desc='Members allowed to authenticate INTO Tier 1 resources via Authentication Policy Silo' }
        )
    }
    @{
        Tier     = 2
        OU       = 'Tier-2'
        Comment  = 'Workstation admins (helpdesk, desktop). Cannot log into servers. Daily user identities live here.'
        Groups   = @(
            @{ Name='Tier-2-Admins';        Scope='Global';     Desc='Tier 2 workstation administrators (helpdesk / desktop support)' }
            @{ Name='Tier-2-Workstations';  Scope='Global';     Desc='Tier 2 workstation computer accounts (end-user devices)' }
            @{ Name='Tier-2-AuthSilo-Users';Scope='Universal';  Desc='Members allowed to authenticate INTO Tier 2 resources via Authentication Policy Silo' }
        )
    }
)

# -- Create parent OU ---------------------------------------------------------
$adminOuName = 'Admin'
$adminOuDn   = "OU=$adminOuName,$OUParent"

Write-Step "Phase 1 - Ensure parent OU exists: $adminOuDn"
$exists = $null
try { $exists = Get-ADOrganizationalUnit -Identity $adminOuDn -ErrorAction SilentlyContinue } catch {}
if ($exists) {
    Write-Skip "OU already exists: $adminOuDn"
} else {
    if ($PSCmdlet.ShouldProcess($adminOuDn, 'Create OU')) {
        if (-not $DryRun) {
            New-ADOrganizationalUnit -Name $adminOuName -Path $OUParent `
                -ProtectedFromAccidentalDeletion $true `
                -Description 'Phase 8.1 - Tiered administrative model (T0/T1/T2)'
        }
        Write-OK "Created: $adminOuDn"
    }
}
Write-Host ''

# -- Create tier OUs and child groups -----------------------------------------
foreach ($t in $tierPlan) {
    Write-Step "Phase 2 - Tier $($t.Tier): $($t.OU)"
    Write-Info "$($t.Comment)"

    $tierOuDn = "OU=$($t.OU),$adminOuDn"

    # OU
    $existsOu = $null
    try { $existsOu = Get-ADOrganizationalUnit -Identity $tierOuDn -ErrorAction SilentlyContinue } catch {}
    if ($existsOu) {
        Write-Skip "OU already exists: $tierOuDn"
    } else {
        if ($PSCmdlet.ShouldProcess($tierOuDn, 'Create tier OU')) {
            if (-not $DryRun) {
                New-ADOrganizationalUnit -Name $t.OU -Path $adminOuDn `
                    -ProtectedFromAccidentalDeletion $true `
                    -Description "Tier $($t.Tier): $($t.Comment)"
            }
            Write-OK "Created OU: $tierOuDn"
        }
    }

    # Groups
    foreach ($g in $t.Groups) {
        $existsGroup = $null
        try { $existsGroup = Get-ADGroup -Identity $g.Name -ErrorAction SilentlyContinue } catch {}
        if ($existsGroup) {
            Write-Skip "Group already exists: $($g.Name)"
            continue
        }
        if ($PSCmdlet.ShouldProcess($g.Name, "Create $($g.Scope) Security Group in $tierOuDn")) {
            if (-not $DryRun) {
                New-ADGroup -Name $g.Name `
                    -SamAccountName $g.Name `
                    -GroupCategory Security `
                    -GroupScope    $g.Scope `
                    -Path $tierOuDn `
                    -Description $g.Desc
            }
            Write-OK "Created group: $($g.Name) ($($g.Scope))"
        }
    }
    Write-Host ''
}

# -- Seed accounts (optional) -------------------------------------------------
if ($CreateSeedAccounts) {
    Write-Step 'Phase 3 - Create seed admin accounts (one per tier)'
    Write-Warn 'Random passwords printed below. Record them BEFORE this terminal closes.'
    Write-Host ''

    foreach ($t in $tierPlan) {
        $samName  = "T$($t.Tier)-Admin"
        $upn      = "$samName@$((Get-ADDomain).DNSRoot)"
        $tierOu   = "OU=$($t.OU),$adminOuDn"
        $adminGrp = "Tier-$($t.Tier)-Admins"

        $existsUser = $null
        try { $existsUser = Get-ADUser -Identity $samName -ErrorAction SilentlyContinue } catch {}
        if ($existsUser) {
            Write-Skip "User already exists: $samName"
            continue
        }

        $pw = New-RandomPassword
        $securePw = ConvertTo-SecureString $pw -AsPlainText -Force

        if ($PSCmdlet.ShouldProcess($samName, "Create seed admin in Tier $($t.Tier)")) {
            if (-not $DryRun) {
                New-ADUser -Name $samName `
                    -SamAccountName $samName `
                    -UserPrincipalName $upn `
                    -GivenName "Tier$($t.Tier)" -Surname 'Admin' `
                    -AccountPassword $securePw `
                    -Enabled $true `
                    -PasswordNeverExpires $false `
                    -ChangePasswordAtLogon $true `
                    -Path $tierOu `
                    -Description "Phase 8.1 seed - Tier $($t.Tier) administrative account"

                Add-ADGroupMember -Identity $adminGrp -Members $samName
            }
            Write-OK "Created: $samName  (initial pw: $pw  - CHANGE ON FIRST LOGON)"
        }
    }
    Write-Host ''
}

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Tier model created. Next steps (in subsequent Phase 8 scripts):' -ForegroundColor White
Write-Host '      - 8.1.2 Set-LeastPrivilegeGPO.ps1     User Rights Assignment per tier' -ForegroundColor Gray
Write-Host '      - 8.1.3 New-RBACModel.ps1             Role groups -> resource mapping' -ForegroundColor Gray
Write-Host '      - 8.1.4 Set-AuthenticationPolicySilo.ps1  Kerberos silos that enforce tier isolation' -ForegroundColor Gray
Write-Host '      - 8.1.5 Deploy-ResourceGateway.ps1    PEP reverse proxy demo' -ForegroundColor Gray
Write-Host '' -ForegroundColor White
Write-Host '    Manual follow-up:' -ForegroundColor Yellow
Write-Host '      1. Move Lab-DC01 computer object into Admin\Tier-0' -ForegroundColor Yellow
Write-Host '      2. Move Lab-Workstation01 + WO02 into Admin\Tier-2 (or workstation-specific OU)' -ForegroundColor Yellow
Write-Host '      3. Add LAB\Administrator to Tier-0-Admins (it is the existing forest-tier identity)' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
