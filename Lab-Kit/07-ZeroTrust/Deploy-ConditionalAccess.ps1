#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.3.2 - Deploys Entra ID Conditional Access policies that extend the
    on-prem PIV/device trust to cloud sessions: require a compliant/trusted
    device, require certificate-based MFA, block legacy auth, and honour the
    automated block group used by the 8.6.3 response loop.

.DESCRIPTION
    Uses the Microsoft.Graph PowerShell SDK. The policies are created in
    REPORT-ONLY state by default (-Enable to enforce) so you can validate impact
    before turning them on - the standard safe rollout for CA.

    Policies created (idempotent by displayName):
      CA001  Require compliant or hybrid-joined device  (device trust -> cloud)
      CA002  Require MFA for all users                   (certificate/FIDO2 strength)
      CA003  Block legacy authentication                 (kills basic-auth bypass)
      CA004  Block the automated-response group          (ZT-Blocked-Users, 8.6.3)

    A break-glass / emergency-access account group is ALWAYS excluded so a bad
    policy cannot lock you out. Supply it with -BreakGlassGroup (created if absent).

    Prerequisites this script verifies / guides:
      * Microsoft.Graph module installed
      * An admin can consent to Policy.ReadWrite.ConditionalAccess + Group.ReadWrite.All
      * PIV/cert federation to Entra is configured separately (CBA in Entra, or
        AD FS) - see the marked block; CA002 assumes a cert-capable auth method.

.PARAMETER BreakGlassGroup
    Group always EXCLUDED from every policy. Default 'CA-BreakGlass'.

.PARAMETER BlockGroup
    Group the response loop adds risky users to. Default 'ZT-Blocked-Users'.

.PARAMETER Enable
    Switch - create policies ENABLED (enforcing). Default: reportOnly.

.PARAMETER DryRun
    Switch - connect and show the plan, but create nothing.

.EXAMPLE
    .\Deploy-ConditionalAccess.ps1                 # report-only rollout

.EXAMPLE
    .\Deploy-ConditionalAccess.ps1 -Enable         # enforce

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.3.2 - Continuous & Conditional Access
    Run on     : Any host with Microsoft.Graph + Global Admin / CA Admin
    Depends on : Entra tenant; PIV/cert federation configured separately
    NIST       : AC-2, AC-3, IA-2, IA-2(11)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BreakGlassGroup = 'CA-BreakGlass',
    [string]$BlockGroup      = 'ZT-Blocked-Users',
    [switch]$Enable,
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

$state = if ($Enable) { 'enabled' } else { 'enabledForReportingButNotEnforced' }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8.3.2 - Conditional Access (Entra)           |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''
Write-Step "Policy state: $state"
Write-Host ''

# -- Module + connection ------------------------------------------------------
if (-not (Get-Module -ListAvailable Microsoft.Graph.Identity.SignIns)) {
    Write-Fatal 'Microsoft.Graph not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser'
}
Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop
Import-Module Microsoft.Graph.Groups -ErrorAction Stop

if (-not (Get-MgContext)) {
    Write-Step 'Connecting to Microsoft Graph (admin consent prompt)...'
    Connect-MgGraph -Scopes 'Policy.ReadWrite.ConditionalAccess','Group.ReadWrite.All','Application.Read.All' | Out-Null
}
$ctx = Get-MgContext
if (-not $ctx) { Write-Fatal 'Not connected to Graph.' }
Write-OK "Connected: tenant $($ctx.TenantId) as $($ctx.Account)"
Write-Host ''

# -- Helper: ensure a security group, return its id ---------------------------
function Confirm-EntraGroup {
    param([string]$Name)
    $g = Get-MgGroup -Filter "displayName eq '$Name'" -Top 1 -ErrorAction SilentlyContinue
    if ($g) { return $g.Id }
    if ($DryRun) { Write-Info "(DryRun) would create group $Name"; return $null }
    if ($PSCmdlet.ShouldProcess($Name, 'Create Entra security group')) {
        $g = New-MgGroup -DisplayName $Name -MailEnabled:$false -SecurityEnabled:$true `
                -MailNickname ($Name -replace '\W','') -Description 'Phase 8.3.2 CA support group'
        Write-OK "Created group: $Name"
        return $g.Id
    }
}

Write-Step 'Phase 1 - Support groups'
$bgId    = Confirm-EntraGroup -Name $BreakGlassGroup
$blockId = Confirm-EntraGroup -Name $BlockGroup
Write-Info "Break-glass group always excluded: $BreakGlassGroup"
Write-Host ''

$excludeUsers = if ($bgId) { @{ excludeGroups = @($bgId) } } else { @{} }

# -- Helper: create a CA policy if missing ------------------------------------
function Confirm-CAPolicy {
    param([string]$Name, [hashtable]$Conditions, [hashtable]$GrantControls)
    $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$Name'" -ErrorAction SilentlyContinue
    if ($existing) { Write-Skip "Policy exists: $Name"; return }
    if ($DryRun) { Write-Info "(DryRun) would create policy: $Name"; return }
    if ($PSCmdlet.ShouldProcess($Name, "Create CA policy ($state)")) {
        $params = @{
            DisplayName   = $Name
            State         = $state
            Conditions    = $Conditions
            GrantControls = $GrantControls
        }
        New-MgIdentityConditionalAccessPolicy -BodyParameter $params | Out-Null
        Write-OK "Created policy: $Name"
    }
}

Write-Step 'Phase 2 - Conditional Access policies'

# CA001 - require compliant or hybrid-joined device
Confirm-CAPolicy -Name 'CA001 - Require compliant or hybrid-joined device' `
    -Conditions @{
        users        = (@{ includeUsers = @('All') } + $excludeUsers)
        applications = @{ includeApplications = @('All') }
        clientAppTypes = @('all')
    } `
    -GrantControls @{ operator = 'OR'; builtInControls = @('compliantDevice','domainJoinedDevice') }

# CA002 - require MFA for all users (cert/FIDO2 strength expected via auth methods)
Confirm-CAPolicy -Name 'CA002 - Require MFA for all users' `
    -Conditions @{
        users        = (@{ includeUsers = @('All') } + $excludeUsers)
        applications = @{ includeApplications = @('All') }
        clientAppTypes = @('all')
    } `
    -GrantControls @{ operator = 'OR'; builtInControls = @('mfa') }

# CA003 - block legacy authentication
Confirm-CAPolicy -Name 'CA003 - Block legacy authentication' `
    -Conditions @{
        users        = (@{ includeUsers = @('All') } + $excludeUsers)
        applications = @{ includeApplications = @('All') }
        clientAppTypes = @('exchangeActiveSync','other')
    } `
    -GrantControls @{ operator = 'OR'; builtInControls = @('block') }

# CA004 - block the automated-response group (8.6.3 loop closer)
if ($blockId) {
    Confirm-CAPolicy -Name 'CA004 - Block ZT response group' `
        -Conditions @{
            users        = @{ includeGroups = @($blockId); excludeGroups = @($bgId) }
            applications = @{ includeApplications = @('All') }
            clientAppTypes = @('all')
        } `
        -GrantControls @{ operator = 'OR'; builtInControls = @('block') }
}
Write-Host ''

# -- PIV / certificate federation note ----------------------------------------
# Cert-based auth to Entra is configured outside CA policy. To make CA002 satisfied
# by the lab PIV/smart-card cert rather than a phone factor:
#   1. Entra admin center > Protection > Authentication methods > Certificate-based
#      authentication > enable, upload the lab Root/Issuing CA, set the username
#      binding (PrincipalName / RFC822) and the authentication binding to MFA.
#   2. (Hybrid) ensure the on-prem UPN matches the Entra UPN so the PIV cert maps.
#   3. Optionally require Authentication Strength = 'Phishing-resistant MFA' on CA002.

Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    CA policies deployed in state: $state" -ForegroundColor White
if (-not $Enable) { Write-Host '    Report-only: review sign-in logs > CA, then re-run with -Enable.' -ForegroundColor Yellow }
Write-Host "    Break-glass group '$BreakGlassGroup' is excluded from all - add 2 cloud-only" -ForegroundColor Yellow
Write-Host '    emergency accounts to it and store their creds offline.' -ForegroundColor Yellow
Write-Host '    Next: New-RiskPolicy.ps1 (8.3.3) layers risk-based step-up/block on top.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
