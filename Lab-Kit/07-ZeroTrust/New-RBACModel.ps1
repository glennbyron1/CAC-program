#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Phase 8.1.3 - Builds an AGDLP role-based access model: defines role groups
    (Helpdesk-L1, FileServer-Admins, AppOwner-CRM, ...) and maps each role to
    the resource-access groups it is allowed to use.

.DESCRIPTION
    Implements Microsoft's AGDLP authorization pattern on top of the tier model
    created by Set-TieredAdminModel.ps1:

      Accounts  ->  Global "role" groups  ->  Domain Local "resource" groups  ->  Permissions

    Roles (Global, "who you are")   live in the tier OU that matches their blast
    radius. Resource groups (Domain Local, "what may be touched") live under
    OU=ResourceAccess. Each role is nested into the resource groups its job
    requires - so granting access is a group-nesting change, never a direct ACE
    on a user.

    The model is data-driven: edit the $roleModel table below to match your
    organisation. Re-running is safe (idempotent) - existing objects are skipped
    and missing memberships are added.

    Resource groups are created empty. You apply them to the actual resource
    (share ACL, app role, SQL login) by hand or in the resource's own script;
    this script only builds the directory side.

.PARAMETER OUParent
    Distinguished name of the domain root. Defaults to the running domain.

.PARAMETER ResourceOUName
    Name of the OU that holds Domain Local resource groups. Default 'ResourceAccess'.

.PARAMETER ExportCsv
    Switch - also write the resolved role->resource map to a timestamped CSV in
    the current directory (evidence for the SSP / access-control matrix).

.PARAMETER DryRun
    Switch - show the plan without writing to AD.

.EXAMPLE
    .\New-RBACModel.ps1

.EXAMPLE
    .\New-RBACModel.ps1 -DryRun -ExportCsv

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.1.3 - Authorization & Least Privilege
    Run on     : Lab-DC01
    Depends on : Set-TieredAdminModel.ps1
    NIST       : AC-2, AC-3, AC-6, AC-6(7)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OUParent       = '',
    [string]$ResourceOUName = 'ResourceAccess',
    [switch]$ExportCsv,
    [switch]$DryRun
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
Write-Host '  |     Phase 8.1.3 - RBAC Model (AGDLP)                 |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Fatal 'ActiveDirectory module not available. Run on Lab-DC01 with RSAT installed.'
}
Import-Module ActiveDirectory -ErrorAction Stop

if (-not $OUParent) { $OUParent = (Get-ADDomain).DistinguishedName }
$adminDn    = "OU=Admin,$OUParent"
$resourceDn = "OU=$ResourceOUName,$OUParent"

Write-Step "Domain root : $OUParent"
Write-Step "Mode        : $(if ($DryRun) { 'DRY RUN (no writes)' } else { 'APPLY' })"
Write-Host ''

# ---------------------------------------------------------------------------
#  THE MODEL  - edit this table to match your organisation.
#  Tier      : which tier OU the (Global) role group lives in (0/1/2).
#  Role      : the Global group people are added to.
#  Resources : Domain Local groups that grant access; the role is nested in each.
# ---------------------------------------------------------------------------
$roleModel = @(
    @{ Tier=2; Role='Role-Helpdesk-L1'
       Desc='First-line helpdesk - reset user passwords, unlock accounts, read workstation status'
       Resources=@(
           @{ Name='Res-Workstations-Support'; Desc='Local admin on Tier-2 workstations (helpdesk support)' }
           @{ Name='Res-UserAccounts-Reset';   Desc='Delegated password reset / unlock on standard user OU' }
       ) }
    @{ Tier=1; Role='Role-FileServer-Admins'
       Desc='File server administrators - manage shares and storage on Tier-1 file servers'
       Resources=@(
           @{ Name='Res-FileServers-Admin';    Desc='Local admin on Tier-1 file servers' }
           @{ Name='Res-FileShares-FullCtrl';  Desc='Full control on departmental file shares' }
       ) }
    @{ Tier=1; Role='Role-AppOwner-CRM'
       Desc='CRM application owner - administers the CRM app servers and app role'
       Resources=@(
           @{ Name='Res-CRM-AppAdmin';         Desc='Local admin on CRM application servers' }
           @{ Name='Res-CRM-AppRole';          Desc='Privileged role inside the CRM application' }
       ) }
    @{ Tier=1; Role='Role-DBA'
       Desc='Database administrators - manage SQL instances on Tier-1 DB servers'
       Resources=@(
           @{ Name='Res-SQL-SysAdmin';         Desc='sysadmin login on lab SQL instances' }
           @{ Name='Res-DBServers-Admin';      Desc='Local admin on Tier-1 database servers' }
       ) }
    @{ Tier=0; Role='Role-PKI-Operators'
       Desc='PKI operators - issue/revoke certs on the Issuing CA (Tier 0)'
       Resources=@(
           @{ Name='Res-IssuingCA-Officers';   Desc='Certificate Manager (officer) role on the Issuing CA' }
       ) }
)

# -- Ensure the ResourceAccess OU exists --------------------------------------
Write-Step "Phase 1 - Resource OU: $resourceDn"
$ouExists = $null
try { $ouExists = Get-ADOrganizationalUnit -Identity $resourceDn -ErrorAction SilentlyContinue } catch {}
if ($ouExists) {
    Write-Skip "OU already exists: $resourceDn"
} elseif ($PSCmdlet.ShouldProcess($resourceDn, 'Create OU')) {
    if (-not $DryRun) {
        New-ADOrganizationalUnit -Name $ResourceOUName -Path $OUParent `
            -ProtectedFromAccidentalDeletion $true `
            -Description 'Phase 8.1.3 - AGDLP Domain Local resource-access groups'
    }
    Write-OK "Created: $resourceDn"
}
Write-Host ''

# -- Helper: create a group if missing ----------------------------------------
function Confirm-Group {
    param([string]$Name, [string]$Scope, [string]$Path, [string]$Desc)
    $g = $null
    try { $g = Get-ADGroup -Identity $Name -ErrorAction SilentlyContinue } catch {}
    if ($g) { Write-Skip "Group exists: $Name"; return }
    if ($PSCmdlet.ShouldProcess($Name, "Create $Scope group in $Path")) {
        if (-not $DryRun) {
            New-ADGroup -Name $Name -SamAccountName $Name -GroupCategory Security `
                -GroupScope $Scope -Path $Path -Description $Desc
        }
        Write-OK "Created $Scope group: $Name"
    }
}

# -- Build roles + resources + nesting ----------------------------------------
$mapRows = @()
foreach ($r in $roleModel) {
    $tierOu = "OU=Tier-$($r.Tier),$adminDn"
    if (-not (Get-ADOrganizationalUnit -Identity $tierOu -ErrorAction SilentlyContinue)) {
        Write-Warn "Tier $($r.Tier) OU not found ($tierOu) - run Set-TieredAdminModel.ps1 first. Skipping role $($r.Role)."
        continue
    }

    Write-Step "Role: $($r.Role)  (Tier $($r.Tier))"
    Write-Info $r.Desc

    # Global role group in the tier OU
    Confirm-Group -Name $r.Role -Scope Global -Path $tierOu -Desc $r.Desc

    foreach ($res in $r.Resources) {
        # Domain Local resource group under ResourceAccess
        Confirm-Group -Name $res.Name -Scope DomainLocal -Path $resourceDn -Desc $res.Desc

        # Nest the role into the resource group (AGDLP)
        $alreadyMember = $false
        if (-not $DryRun) {
            try {
                $alreadyMember = [bool](Get-ADGroupMember -Identity $res.Name -ErrorAction SilentlyContinue |
                    Where-Object { $_.SamAccountName -eq $r.Role })
            } catch {}
        }
        if ($alreadyMember) {
            Write-Skip "Already nested: $($r.Role) -> $($res.Name)"
        } elseif ($PSCmdlet.ShouldProcess("$($r.Role) -> $($res.Name)", 'Nest role into resource group')) {
            if (-not $DryRun) { Add-ADGroupMember -Identity $res.Name -Members $r.Role }
            Write-OK "Nested: $($r.Role) -> $($res.Name)"
        }

        $mapRows += [pscustomobject]@{
            Tier         = $r.Tier
            Role         = $r.Role
            ResourceGroup= $res.Name
            ResourceDesc = $res.Desc
        }
    }
    Write-Host ''
}

# -- Optional CSV export ------------------------------------------------------
if ($ExportCsv -and $mapRows.Count -gt 0) {
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $csv   = Join-Path (Get-Location) "RBAC-Model_$stamp.csv"
    $mapRows | Sort-Object Tier, Role, ResourceGroup | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-OK "Access-control matrix exported: $csv"
    Write-Host ''
}

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    Roles defined      : $(($roleModel | Measure-Object).Count)" -ForegroundColor White
Write-Host "    Resource groups    : $(($mapRows | Select-Object -ExpandProperty ResourceGroup -Unique | Measure-Object).Count)" -ForegroundColor White
Write-Host '' -ForegroundColor White
Write-Host '    Next steps (manual - resource side):' -ForegroundColor Yellow
Write-Host '      1. Add people to the Role-* groups (membership = job function).' -ForegroundColor Yellow
Write-Host '      2. Apply each Res-* group to its resource:' -ForegroundColor Yellow
Write-Host '           - file share ACL  : grant Res-FileShares-FullCtrl' -ForegroundColor Yellow
Write-Host '           - local admin     : GPO Restricted Groups / LAPS scope' -ForegroundColor Yellow
Write-Host '           - SQL / app role  : map the Res-* group to the app login' -ForegroundColor Yellow
Write-Host '      3. Never put a person directly on a resource ACL - only Res-* groups.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
Write-Host ''
