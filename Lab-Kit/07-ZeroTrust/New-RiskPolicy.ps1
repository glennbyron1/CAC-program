#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.3.3 - Defines the risk-to-response policy: which risk level triggers
    step-up, containment, or block. Publishes a canonical policy file the on-prem
    response loop (8.6.3) reads, and optionally deploys Entra risk-based
    Conditional Access policies.

.DESCRIPTION
    Risk signals come from Defender XDR, Entra Identity Protection, or your SIEM
    (the 8.6.2 detections). This script is the DECISION layer that turns a risk
    level into an action, in two places that stay in sync:

      1. On-prem policy file (always): writes risk-policy.json under ProgramData
         describing tiers Low/Medium/High and the action + groups each maps to.
         Connect-Analytics-To-Policy.ps1 (8.6.3) reads this so the response engine
         and the policy definition never drift. It also ensures the referenced AD
         groups exist (step-up, containment).

      2. Entra risk-based CA (optional, -UseGraph): creates Conditional Access
         policies keyed on sign-in risk and user risk. Requires Entra ID P2
         (Identity Protection). Created report-only unless -Enable.
            RISK-SignIn-High   -> block
            RISK-SignIn-Medium -> require MFA
            RISK-User-High     -> require secure password change + MFA

    Re-running is safe; the policy file is rewritten and existing CA policies /
    groups are reused.

.PARAMETER StepUpGroup
    AD group for "watch / step-up at next logon". Default 'ZT-StepUp'.

.PARAMETER ContainGroup
    AD group for containment (deny-logon). Default 'ZT-HighRisk-Deny'.

.PARAMETER PolicyPath
    Where to write the canonical policy JSON. Default
    "$env:ProgramData\CAC-Program\ZeroTrust\risk-policy.json".

.PARAMETER UseGraph
    Switch - also deploy Entra risk-based CA policies (needs Entra ID P2).

.PARAMETER Enable
    Switch - create the Entra policies enforcing (default report-only).

.PARAMETER DryRun
    Switch - preview without writing the file, AD groups, or CA policies.

.EXAMPLE
    .\New-RiskPolicy.ps1

.EXAMPLE
    .\New-RiskPolicy.ps1 -UseGraph -Enable

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.3.3 - Continuous & Conditional Access
    Run on     : Lab-DC01 (policy file + AD groups) / Entra-connected host (-UseGraph)
    Depends on : Conditional Access (8.3.2), SIEM detections (8.6.2)
    NIST       : AC-2(12), IA-2(12), SI-4(24)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StepUpGroup  = 'ZT-StepUp',
    [string]$ContainGroup = 'ZT-HighRisk-Deny',
    [string]$PolicyPath   = "$env:ProgramData\CAC-Program\ZeroTrust\risk-policy.json",
    [switch]$UseGraph,
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

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8.3.3 - Risk Policy (decision layer)         |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# -- The canonical risk -> response model -------------------------------------
$policy = [ordered]@{
    Schema      = 'cac-zt-risk-policy/1'
    GeneratedAt = (Get-Date).ToString('o')
    StepUpGroup = $StepUpGroup
    ContainGroup= $ContainGroup
    Tiers = @(
        [ordered]@{ Level='Low';    Action='StepUp';  Group=$StepUpGroup
                    Desc='Log + require fresh auth at next sign-in. No active containment.' }
        [ordered]@{ Level='Medium'; Action='Contain'; Group=$ContainGroup
                    Desc='Add to deny-logon group; revoke nothing immediately; analyst review.' }
        [ordered]@{ Level='High';   Action='Block';   Group=$ContainGroup
                    Desc='Add to deny-logon group AND revoke active Kerberos tickets immediately.' }
    )
    # detection-id -> risk level (kept aligned with New-DetectionRules.ps1)
    RuleRisk = [ordered]@{
        'ZT-001'='High'; 'ZT-002'='High'; 'ZT-003'='Medium'; 'ZT-004'='Medium'
        'ZT-005'='High'; 'ZT-006'='Medium'; 'ZT-007'='Low'
    }
}

# -- 1. Write the policy file -------------------------------------------------
Write-Step "Phase 1 - Canonical policy file: $PolicyPath"
$dir = Split-Path $PolicyPath -Parent
if (-not (Test-Path $dir)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
if ($DryRun) {
    Write-Info '(DryRun) would write policy JSON:'
    Write-Info ($policy | ConvertTo-Json -Depth 5)
} elseif ($PSCmdlet.ShouldProcess($PolicyPath, 'Write risk policy JSON')) {
    $policy | ConvertTo-Json -Depth 5 | Set-Content -Path $PolicyPath -Encoding UTF8
    Write-OK 'Policy file written (8.6.3 reads this to choose responses)'
}
Write-Host ''

# -- 2. Ensure the referenced AD groups exist ---------------------------------
Write-Step 'Phase 2 - Referenced AD groups'
if (Get-Module -ListAvailable ActiveDirectory) {
    Import-Module ActiveDirectory -ErrorAction Stop
    foreach ($grp in @($StepUpGroup, $ContainGroup)) {
        $g = $null
        try { $g = Get-ADGroup -Identity $grp -ErrorAction SilentlyContinue } catch {}
        if ($g) { Write-Skip "Group exists: $grp"; continue }
        if ($PSCmdlet.ShouldProcess($grp, 'Create AD group')) {
            if (-not $DryRun) {
                New-ADGroup -Name $grp -SamAccountName $grp -GroupScope DomainLocal -GroupCategory Security `
                    -Path (Get-ADDomain).UsersContainer -Description "Phase 8.3.3 risk-response group ($grp)"
            }
            Write-OK "Created group: $grp"
        }
    }
    Write-Warn "Link a 'Deny log on locally / through RDP' GPO to $ContainGroup if not already done."
} else {
    Write-Warn 'ActiveDirectory module not available here - create the groups on Lab-DC01.'
}
Write-Host ''

# -- 3. Optional Entra risk-based CA ------------------------------------------
if ($UseGraph) {
    Write-Step 'Phase 3 - Entra risk-based Conditional Access (Identity Protection / P2)'
    if (-not (Get-Module -ListAvailable Microsoft.Graph.Identity.SignIns)) {
        Write-Warn 'Microsoft.Graph not installed - skipping Entra risk policies.'
    } else {
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop
        if (-not (Get-MgContext)) { Connect-MgGraph -Scopes 'Policy.ReadWrite.ConditionalAccess' | Out-Null }
        $state = if ($Enable) { 'enabled' } else { 'enabledForReportingButNotEnforced' }

        function Confirm-RiskCA {
            param([string]$Name, [string[]]$SignInRisk, [string[]]$UserRisk, [string[]]$Controls)
            if (Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$Name'" -ErrorAction SilentlyContinue) {
                Write-Skip "Policy exists: $Name"; return
            }
            if ($DryRun) { Write-Info "(DryRun) would create $Name"; return }
            $cond = @{
                users          = @{ includeUsers = @('All') }
                applications   = @{ includeApplications = @('All') }
                clientAppTypes = @('all')
            }
            if ($SignInRisk) { $cond['signInRiskLevels'] = $SignInRisk }
            if ($UserRisk)   { $cond['userRiskLevels']   = $UserRisk }
            if ($PSCmdlet.ShouldProcess($Name, "Create risk CA ($state)")) {
                New-MgIdentityConditionalAccessPolicy -BodyParameter @{
                    DisplayName='RISK - '+$Name; State=$state; Conditions=$cond
                    GrantControls=@{ operator='OR'; builtInControls=$Controls }
                } | Out-Null
                Write-OK "Created: RISK - $Name"
            }
        }

        Confirm-RiskCA -Name 'SignIn-High Block'   -SignInRisk @('high')          -Controls @('block')
        Confirm-RiskCA -Name 'SignIn-Medium MFA'   -SignInRisk @('medium')        -Controls @('mfa')
        Confirm-RiskCA -Name 'User-High Step-Up'   -UserRisk   @('high')          -Controls @('mfa','passwordChange')
        Write-Warn 'Risk-based CA requires Entra ID P2 (Identity Protection). Report-only unless -Enable.'
    }
    Write-Host ''
}

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Risk tiers: Low->StepUp, Medium->Contain, High->Block.' -ForegroundColor White
Write-Host "    On-prem source of truth: $PolicyPath" -ForegroundColor White
Write-Host '    The 8.6.3 loop reads this file; keep rule->risk in sync with New-DetectionRules.ps1.' -ForegroundColor Yellow
if ($UseGraph) { Write-Host '    Entra risk policies deployed (report-only unless -Enable).' -ForegroundColor Yellow }
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
