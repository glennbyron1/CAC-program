#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.6.2 - Authors a starter detection pack aligned to the ZT controls in
    8.1-8.5. Emits portable Sigma rules (YAML) for any SIEM, and optionally wires
    the same logic as native event-triggered tasks against the WEC collector.

.DESCRIPTION
    Each detection maps to MITRE ATT&CK and to the control it watches:

      ZT-001  Cross-tier logon            T1078.002  (violates 8.1 tier model)
      ZT-002  Kerberoast burst            T1558.003  (service-ticket spray vs 8.4)
      ZT-003  New service install         T1543.003  (persistence)
      ZT-004  New scheduled task          T1053.005  (persistence)
      ZT-005  Sensitive group change      T1098 / T1484 (privilege escalation)
      ZT-006  Encoded PowerShell          T1059.001  (defense evasion)
      ZT-007  CA cert issued off-hours    T1649      (PKI abuse vs 8.2/8.4)

    Sigma output (always): writes one .yml per rule to -OutPath. Convert to your
    SIEM's query language with `sigma convert` (sigmac), or import directly where
    supported. This keeps the detections vendor-neutral.

    Native output (-RegisterTasks): for the in-box WEC path (Deploy-SIEM.ps1),
    registers scheduled tasks triggered by the matching ForwardedEvents records,
    each launching -OnDetectScript with the event context. That closes the loop
    into Connect-Analytics-To-Policy.ps1 (8.6.3) without an external SIEM.

.PARAMETER OutPath
    Directory for the Sigma .yml files. Default '.\detections'.

.PARAMETER RegisterTasks
    Switch - also register native event-triggered scheduled tasks on this WEC host.

.PARAMETER OnDetectScript
    Script invoked by native tasks when a detection fires. Default points at
    Connect-Analytics-To-Policy.ps1 in this folder.

.PARAMETER DryRun
    Switch - preview without writing files or registering tasks.

.EXAMPLE
    .\New-DetectionRules.ps1

.EXAMPLE
    .\New-DetectionRules.ps1 -RegisterTasks

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.6.2 - Visibility -> Decisioning
    Run on     : SIEM admin workstation (Sigma) / the WEC host (-RegisterTasks)
    Depends on : Deployed SIEM (8.6.1) with event stream
    NIST       : SI-4, SI-4(4), AU-6(1)
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutPath        = '.\detections',
    [switch]$RegisterTasks,
    [string]$OnDetectScript = '',
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
Write-Host '  |   Phase 8.6.2 - Detection Rules (Sigma + native)     |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# Resolve $OnDetectScript to an absolute path NOW (at task-registration time).
# When the scheduled task fires as SYSTEM later, its working directory is
# %SystemRoot%\System32 and $PSScriptRoot inside that powershell.exe invocation
# does not refer to this folder. The task action must store a fully-qualified
# path or it will fail to find the responder.
if (-not $OnDetectScript) { $OnDetectScript = Join-Path $PSScriptRoot 'Connect-Analytics-To-Policy.ps1' }
try {
    $OnDetectScript = (Resolve-Path -LiteralPath $OnDetectScript -ErrorAction Stop).Path
} catch {
    # If the file does not exist yet, fall back to a non-resolved absolute path
    # built from $PSScriptRoot so the task action at least contains an absolute
    # spec (not a relative one). Test-Path check below still warns the operator.
    if (-not [System.IO.Path]::IsPathRooted($OnDetectScript)) {
        $OnDetectScript = Join-Path (Resolve-Path -LiteralPath $PSScriptRoot).Path (Split-Path -Leaf $OnDetectScript)
    }
}
Write-Info "OnDetectScript (absolute): $OnDetectScript"

# -- Detection pack -----------------------------------------------------------
# Channel/EventID + the Sigma detection body + the XPath for native triggers.
$rules = @(
    @{ Id='ZT-001'; Title='Cross-tier interactive logon'; Level='high'; Attack='T1078.002'
       Channel='Security'; EventId=4624
       Desc='A Tier-0/1 admin account logged on interactively to a lower-tier host - violates the 8.1 tier model.'
       Detection=@'
    selection:
        EventID: 4624
        LogonType:
            - 2   # interactive
            - 10  # remote interactive
        TargetUserName|startswith:
            - 'T0-'
            - 'T1-'
    filter_tier0_hosts:
        Computer|startswith: 'Lab-DC'
    condition: selection and not filter_tier0_hosts
'@
       XPath="*[System[(EventID=4624)]] and *[EventData[Data[@Name='TargetUserName'] and (starts-with(Data,'T0-') or starts-with(Data,'T1-'))]]" }

    @{ Id='ZT-002'; Title='Kerberoasting - service ticket burst (RC4)'; Level='high'; Attack='T1558.003'
       Channel='Security'; EventId=4769
       Desc='Many TGS requests with RC4 encryption in a short window - classic Kerberoast harvesting.'
       Detection=@'
    selection:
        EventID: 4769
        TicketEncryptionType: '0x17'   # RC4-HMAC
    timeframe: 5m
    condition: selection | count() by IpAddress > 10
'@
       XPath="*[System[(EventID=4769)]] and *[EventData[Data[@Name='TicketEncryptionType']='0x17']]" }

    @{ Id='ZT-003'; Title='New service installed'; Level='medium'; Attack='T1543.003'
       Channel='Security'; EventId=4697
       Desc='A new Windows service was installed - common persistence mechanism.'
       Detection=@'
    selection:
        EventID: 4697
    condition: selection
'@
       XPath="*[System[(EventID=4697)]]" }

    @{ Id='ZT-004'; Title='Scheduled task created'; Level='medium'; Attack='T1053.005'
       Channel='Security'; EventId=4698
       Desc='A scheduled task was created - persistence / lateral movement.'
       Detection=@'
    selection:
        EventID: 4698
    condition: selection
'@
       XPath="*[System[(EventID=4698)]]" }

    @{ Id='ZT-005'; Title='Sensitive group membership change'; Level='high'; Attack='T1098'
       Channel='Security'; EventId=4728
       Desc='Member added to a security-enabled global group (Domain/Enterprise/Tier-0 admins).'
       Detection=@'
    selection:
        EventID:
            - 4728  # global group
            - 4732  # local group
            - 4756  # universal group
        TargetUserName|contains:
            - 'Admins'
            - 'Tier-0'
    condition: selection
'@
       XPath="*[System[(EventID=4728 or EventID=4732 or EventID=4756)]]" }

    @{ Id='ZT-006'; Title='Encoded / suspicious PowerShell'; Level='high'; Attack='T1059.001'
       Channel='Microsoft-Windows-PowerShell/Operational'; EventId=4104
       Desc='Script block logging captured an encoded or obfuscated command.'
       Detection=@'
    selection:
        EventID: 4104
        ScriptBlockText|contains:
            - '-enc'
            - 'FromBase64String'
            - 'IEX (New-Object Net.WebClient)'
            - 'DownloadString'
    condition: selection
'@
       XPath="*[System[(EventID=4104)]]" }

    @{ Id='ZT-007'; Title='Certificate issued outside business hours'; Level='medium'; Attack='T1649'
       Channel='Security'; EventId=4886
       Desc='AD CS issued a certificate request off-hours - possible PKI abuse.'
       Detection=@'
    selection:
        EventID:
            - 4886  # cert request received
            - 4887  # cert approved/issued
    condition: selection
    # tune off-hours in your SIEM (e.g. NOT between 06:00-20:00 local)
'@
       XPath="*[System[(EventID=4886 or EventID=4887)]]" }
)

# -- Emit Sigma YAML ----------------------------------------------------------
Write-Step "Phase 1 - Sigma rules -> $OutPath"
if (-not (Test-Path $OutPath)) {
    if ($PSCmdlet.ShouldProcess($OutPath, 'Create output dir')) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $OutPath -Force | Out-Null }
    }
}

foreach ($r in $rules) {
    $file = Join-Path $OutPath "$($r.Id)_$($r.Title -replace '[^A-Za-z0-9]+','-').yml"
    $yaml = @"
title: $($r.Title)
id: $($r.Id)
status: experimental
description: $($r.Desc)
references:
    - https://attack.mitre.org/techniques/$($r.Attack.Replace('.','/'))/
author: Glenn Byron (CAC-Program Phase 8.6.2)
tags:
    - attack.$($r.Attack.ToLower())
logsource:
    product: windows
    service: $(if ($r.Channel -eq 'Security') { 'security' } else { 'powershell' })
detection:
$($r.Detection.TrimEnd())
level: $($r.Level)
"@
    if ($DryRun) {
        Write-Info "(DryRun) would write $file"
    } else {
        Set-Content -Path $file -Value $yaml -Encoding UTF8
        Write-OK "$($r.Id)  $($r.Title)"
    }
}
Write-Host ''

# -- Optional: native event-triggered tasks (WEC path) ------------------------
if ($RegisterTasks) {
    Write-Step 'Phase 2 - Native event-triggered detections (ForwardedEvents)'
    if (-not (Test-Path $OnDetectScript)) {
        Write-Warn "OnDetectScript not found: $OnDetectScript - tasks will be created but the action will fail until it exists."
    }

    foreach ($r in $rules) {
        $taskName = "ZT-Detect-$($r.Id)"
        $subscription = @"
<QueryList><Query Id="0" Path="ForwardedEvents"><Select Path="ForwardedEvents">$($r.XPath)</Select></Query></QueryList>
"@
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Write-Skip "Task exists: $taskName"
            continue
        }
        if ($PSCmdlet.ShouldProcess($taskName, 'Register event-triggered detection')) {
            if (-not $DryRun) {
                $trigger = New-CimInstance -CimClass (Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler) -ClientOnly
                $trigger.Subscription = $subscription
                $trigger.Enabled = $true
                $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
                    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$OnDetectScript`" -RuleId $($r.Id) -Source WEC"
                $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
                Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Principal $principal `
                    -Description "Phase 8.6.2 $($r.Id): $($r.Title) [$($r.Attack)]" | Out-Null
            }
            Write-OK "Registered: $taskName"
        }
    }
    Write-Host ''
}

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host "    $($rules.Count) detections authored (Sigma in $OutPath)." -ForegroundColor White
if ($RegisterTasks) {
    Write-Host '    Native triggers registered - each fires Connect-Analytics-To-Policy.ps1.' -ForegroundColor White
} else {
    Write-Host "    Convert for your SIEM:  sigma convert -t <backend> $OutPath" -ForegroundColor Yellow
    Write-Host '    Or re-run with -RegisterTasks to wire them natively to the WEC host.' -ForegroundColor Yellow
}
Write-Host '    Next: Connect-Analytics-To-Policy.ps1 turns a detection into an access action.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
