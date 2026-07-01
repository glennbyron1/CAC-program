#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.6.3 - Closes the loop: turns a SIEM/WEC detection into a concrete
    access decision. A fired detection degrades the implicated user's posture
    automatically (on-prem deny group + ticket revocation; optional Entra block).

.DESCRIPTION
    This is the action end of the detect->decide->respond loop. It is invoked:
      - by the native event-triggered tasks from New-DetectionRules.ps1
        (-RegisterTasks), which call it as: -RuleId ZT-00x -Source WEC
      - or manually / by an external SIEM webhook with -RuleId and -TargetUser.

    Flow:
      1. Resolve the implicated user. If -TargetUser is omitted and -Source WEC,
         the latest matching ForwardedEvents record is parsed for the subject.
      2. Map the rule to a response severity (Step-Up / Contain / Block).
      3. Apply the on-prem response:
           Contain/Block -> add user to 'ZT-HighRisk-Deny' (a Domain Local group
                            you reference from a deny-logon GPO and/or a CA group)
           Block         -> also revoke active Kerberos tickets by bumping the
                            account (disable+enable) so existing TGTs die fast
           All           -> write an auditable event to a custom ZT event log
      4. OPTIONAL: if -UseGraph and Microsoft.Graph is available, add the user to
         the Entra group that Deploy-ConditionalAccess.ps1 blocks, propagating the
         same decision to cloud sessions.

    Designed to be safe to re-run and to fail soft (logs and continues) so a
    detection storm cannot crash the responder.

.PARAMETER RuleId
    Detection id that fired (e.g. ZT-001). Drives the response severity.

.PARAMETER Source
    Where the alert came from: WEC | SIEM | Manual. Default Manual.

.PARAMETER TargetUser
    sAMAccountName of the implicated user. If omitted with -Source WEC, resolved
    from the latest matching event.

.PARAMETER DenyGroup
    On-prem containment group. Default 'ZT-HighRisk-Deny'.

.PARAMETER UseGraph
    Switch - also push the block to Entra via Microsoft.Graph.

.PARAMETER EntraBlockGroup
    Entra group the CA policy blocks. Default 'ZT-Blocked-Users'.

.PARAMETER DryRun
    Switch - decide and log, but apply no changes.

.EXAMPLE
    .\Connect-Analytics-To-Policy.ps1 -RuleId ZT-001 -TargetUser jdoe

.EXAMPLE
    # As invoked by the native WEC trigger
    .\Connect-Analytics-To-Policy.ps1 -RuleId ZT-005 -Source WEC

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.6.3 - Visibility -> Decisioning
    Run on     : The WEC host (native) or any Entra-connected admin host (-UseGraph)
    Depends on : New-DetectionRules.ps1 (8.6.2), Deploy-ConditionalAccess.ps1 (8.3.2)
    NIST       : AC-2(12), SI-4(24)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$RuleId,
    [ValidateSet('WEC','SIEM','Manual')][string]$Source = 'Manual',
    [string]$TargetUser      = '',
    [string]$DenyGroup       = 'ZT-HighRisk-Deny',
    [switch]$UseGraph,
    [string]$EntraBlockGroup = 'ZT-Blocked-Users',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }

# severity map: which response a given rule triggers
$severityMap = @{
    'ZT-001' = 'Block'    # cross-tier logon - hard stop
    'ZT-002' = 'Block'    # kerberoast - hard stop
    'ZT-003' = 'Contain'  # new service
    'ZT-004' = 'Contain'  # scheduled task
    'ZT-005' = 'Block'    # sensitive group change
    'ZT-006' = 'Contain'  # encoded PowerShell
    'ZT-007' = 'StepUp'   # off-hours cert
}

# rule -> the event field that carries the subject, for WEC auto-resolve
$subjectField = @{
    'ZT-001' = 'TargetUserName'
    'ZT-002' = 'TargetUserName'
    'ZT-003' = 'SubjectUserName'
    'ZT-004' = 'SubjectUserName'
    'ZT-005' = 'SubjectUserName'
    'ZT-006' = 'SubjectUserName'
    'ZT-007' = 'SubjectUserName'
}

# rule -> the EventID(s) this detection fires on, for narrow ForwardedEvents lookup.
# These mirror the channels Deploy-SIEM.ps1 subscribes to and the rules
# New-DetectionRules.ps1 emits. Used to filter Get-WinEvent precisely instead
# of regex-matching the human-readable Message text.
$ruleEventIds = @{
    'ZT-001' = @(4624,4625)              # cross-tier interactive logon
    'ZT-002' = @(4769)                   # Kerberos service ticket (kerberoast indicator)
    'ZT-003' = @(7045,4697)              # new service installed
    'ZT-004' = @(4698)                   # scheduled task created
    'ZT-005' = @(4728,4732,4756)         # privileged-group member added
    'ZT-006' = @(4104)                   # PS script-block (encoded command)
    'ZT-007' = @(4768,4769)              # off-hours cert / Kerberos TGT
}

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8.6.3 - Analytics -> Policy (loop closer)    |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

$severity = if ($severityMap.ContainsKey($RuleId)) { $severityMap[$RuleId] } else { 'Contain' }
Write-Step "Detection : $RuleId  (source: $Source)"
Write-Step "Response  : $severity"

# -- ensure a place to audit our decisions ------------------------------------
$logName = 'ZeroTrust-Response'
$srcName = 'ZT-Analytics'
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($srcName)) {
        if (-not $DryRun) { New-EventLog -LogName $logName -Source $srcName -ErrorAction Stop }
    }
} catch { Write-Warn "Could not register event source (need admin): $($_.Exception.Message.Split([char]10)[0])" }

function Write-ZTAudit {
    param([string]$Message, [int]$EventId = 8600, [string]$EntryType = 'Warning')
    try {
        if (-not $DryRun -and [System.Diagnostics.EventLog]::SourceExists($srcName)) {
            Write-EventLog -LogName $logName -Source $srcName -EventId $EventId -EntryType $EntryType -Message $Message
        }
    } catch {}
}

# -- resolve the implicated user ----------------------------------------------
# Pre-review fix: the prior implementation called Get-WinEvent and then ran
# `$_.Message -match $field` over the human-readable Message text. Field names
# like "SubjectUserName" appear in nearly every Security event's rendered
# Message, so the filter was effectively a no-op (it returned the most recent
# event in the log, regardless of relevance). Replaced with a structured
# FilterHashtable that narrows on the specific EventID(s) the rule fires on.
if (-not $TargetUser -and $Source -eq 'WEC') {
    Write-Step 'Resolving target user from latest matching ForwardedEvents record'
    $field = if ($subjectField.ContainsKey($RuleId)) { $subjectField[$RuleId] } else { 'SubjectUserName' }
    $ids   = if ($ruleEventIds.ContainsKey($RuleId)) { $ruleEventIds[$RuleId] } else { @() }
    try {
        if ($ids.Count -gt 0) {
            # Structured filter: only events with the right Id on the ForwardedEvents channel.
            $events = Get-WinEvent -FilterHashtable @{ LogName = 'ForwardedEvents'; Id = $ids } -MaxEvents 50 -ErrorAction Stop
        } else {
            Write-Warn "No EventID mapping for rule '$RuleId'; falling back to ForwardedEvents tail (unfiltered)."
            $events = Get-WinEvent -LogName ForwardedEvents -MaxEvents 50 -ErrorAction Stop
        }
        # Walk newest -> oldest; first event whose EventData carries the named field wins.
        foreach ($evt in $events) {
            $xml = [xml]$evt.ToXml()
            $node = $xml.Event.EventData.Data | Where-Object { $_.Name -eq $field }
            if ($node -and $node.'#text') {
                $TargetUser = $node.'#text'
                break
            }
        }
    } catch { Write-Warn "Event lookup failed: $($_.Exception.Message.Split([char]10)[0])" }
}

if (-not $TargetUser -or $TargetUser -in @('-','SYSTEM','ANONYMOUS LOGON')) {
    Write-Warn "No actionable user resolved (got '$TargetUser'). Logging the detection only."
    Write-ZTAudit -Message "$RuleId from $Source fired but no actionable user was resolved." -EventId 8601 -EntryType Information
    Write-Host ''
    return
}
$TargetUser = $TargetUser.TrimEnd('$')
Write-OK "Implicated user: $TargetUser"
Write-Host ''

if ($severity -eq 'StepUp') {
    Write-Step 'Response: Step-Up (no containment, flag for re-auth)'
    Write-Info 'Off-hours / low-severity: recorded for analyst review and step-up at next sign-in.'
    Write-ZTAudit -Message "${RuleId}: step-up flagged for $TargetUser (source $Source)." -EventId 8602 -EntryType Information
    Write-OK 'Logged. No access change applied.'
    Write-Host ''
    return
}

# -- on-prem containment ------------------------------------------------------
Write-Step "Response: $severity (on-prem containment)"
try {
    Import-Module ActiveDirectory -ErrorAction Stop

    # ensure deny group
    $g = $null
    try { $g = Get-ADGroup -Identity $DenyGroup -ErrorAction SilentlyContinue } catch {}
    if (-not $g) {
        if ($PSCmdlet.ShouldProcess($DenyGroup, 'Create containment group')) {
            if (-not $DryRun) {
                New-ADGroup -Name $DenyGroup -SamAccountName $DenyGroup -GroupScope DomainLocal `
                    -GroupCategory Security -Path (Get-ADDomain).UsersContainer `
                    -Description 'Phase 8.6.3 - users contained by automated ZT response. Referenced by deny-logon GPO + CA group.'
            }
            Write-OK "Created containment group: $DenyGroup"
            Write-Warn "Link a 'Deny log on locally/through RDP' GPO to this group if not already done."
        }
    }

    # add user to deny group
    $isMember = $false
    if (-not $DryRun) {
        try { $isMember = [bool](Get-ADGroupMember -Identity $DenyGroup -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $TargetUser }) } catch {}
    }
    if ($isMember) {
        Write-Info "$TargetUser already contained in $DenyGroup"
    } elseif ($PSCmdlet.ShouldProcess($TargetUser, "Add to $DenyGroup")) {
        if (-not $DryRun) { Add-ADGroupMember -Identity $DenyGroup -Members $TargetUser }
        Write-OK "Contained: $TargetUser -> $DenyGroup"
    }

    # Block = also kill active Kerberos sessions fast (disable+enable bumps the account).
    # Capture original Enabled state FIRST - if the account was already disabled
    # (e.g. service account, pre-detection lockout), we must NOT re-enable it.
    if ($severity -eq 'Block') {
        if ($PSCmdlet.ShouldProcess($TargetUser, 'Revoke Kerberos tickets (disable+re-enable)')) {
            if (-not $DryRun) {
                $wasEnabled = $false
                try {
                    $wasEnabled = [bool](Get-ADUser -Identity $TargetUser -Properties Enabled -ErrorAction Stop).Enabled
                } catch {
                    Write-Warn "Could not read Enabled state for $TargetUser ($($_.Exception.Message.Split([char]10)[0])) - skipping ticket-revoke bounce."
                }
                if ($wasEnabled) {
                    Disable-ADAccount -Identity $TargetUser
                    Start-Sleep -Seconds 2
                    Enable-ADAccount  -Identity $TargetUser   # deny GPO holds the line; account returns to its prior Enabled=true state
                    Write-OK "Existing Kerberos tickets for $TargetUser invalidated (account was Enabled; re-enabled after bounce)"
                } else {
                    Write-Skip "$TargetUser was already Disabled - leaving disabled (no ticket-bounce needed)"
                }
            } else {
                Write-OK "DRYRUN: would invalidate Kerberos tickets for $TargetUser if Enabled"
            }
        }
    }

    Write-ZTAudit -Message "$RuleId ($severity): $TargetUser contained in $DenyGroup (source $Source)." -EventId 8603 -EntryType Warning
} catch {
    Write-Warn "On-prem response failed: $($_.Exception.Message.Split([char]10)[0])"
}
Write-Host ''

# -- optional Entra propagation -----------------------------------------------
if ($UseGraph) {
    Write-Step 'Response: propagate block to Entra (Conditional Access)'
    if (-not (Get-Module -ListAvailable Microsoft.Graph.Groups)) {
        Write-Warn 'Microsoft.Graph module not installed - skipping cloud propagation.'
    } else {
        try {
            Import-Module Microsoft.Graph.Groups -ErrorAction Stop
            if (-not (Get-MgContext)) { Connect-MgGraph -Scopes 'Group.ReadWrite.All','User.Read.All' | Out-Null }
            # Resolve the on-prem user's actual UPN so the Graph lookup uses an
            # exact-match `eq` filter rather than a prefix match. A prefix match
            # against a sAMAccountName like "jsmith" can resolve to "jsmithson"
            # if both exist - wrong person gets their cloud sessions blocked.
            $upnLookup = $null
            try {
                $upnLookup = (Get-ADUser -Identity $TargetUser -Properties UserPrincipalName -ErrorAction Stop).UserPrincipalName
            } catch {
                Write-Warn "Could not read UPN for $TargetUser from AD; falling back to a strict eq lookup keyed on the raw value."
            }
            # OData escape: single quotes inside filter strings must be doubled.
            $escGroup = $EntraBlockGroup -replace "'","''"
            $grp = Get-MgGroup -Filter "displayName eq '$escGroup'" -Top 1
            $user = $null
            if ($upnLookup) {
                $escUpn = $upnLookup -replace "'","''"
                $user = Get-MgUser -Filter "userPrincipalName eq '$escUpn'" -Top 1
            } else {
                # Last-resort: try eq against the raw value as if it were already a UPN.
                $escUser = $TargetUser -replace "'","''"
                $user = Get-MgUser -Filter "userPrincipalName eq '$escUser'" -Top 1
            }
            if ($grp -and $user) {
                if (-not $DryRun) {
                    New-MgGroupMember -GroupId $grp.Id -DirectoryObjectId $user.Id -ErrorAction SilentlyContinue
                }
                Write-OK "Added $TargetUser to Entra group '$EntraBlockGroup' (CA will block)."
            } else {
                Write-Warn "Could not resolve Entra group '$EntraBlockGroup' or user '$TargetUser'."
            }
        } catch {
            Write-Warn "Graph propagation failed: $($_.Exception.Message.Split([char]10)[0])"
        }
    }
    Write-Host ''
}

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    $RuleId -> $severity applied to $TargetUser." -ForegroundColor White
Write-Host "    Audit trail: event log '$logName' (source $srcName)." -ForegroundColor White
Write-Host '    Release a user after investigation:' -ForegroundColor Yellow
Write-Host "      Remove-ADGroupMember -Identity $DenyGroup -Members $TargetUser" -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
