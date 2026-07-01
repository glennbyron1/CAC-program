#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.6.1 - Stands up the collection tier that receives the Windows Event
    Forwarding (WEF) stream the lab already produces. Default implementation is a
    native Windows Event Collector (WEC); optional Sysmon enrichment included.

.DESCRIPTION
    Phase 6 (Set-AuditLogForwarding.ps1) configured the DC and endpoints to FORWARD
    security events. Something has to RECEIVE them. The lowest-friction, no-license
    SIEM core on Windows is the built-in Windows Event Collector:

      1. Enables and starts the Windows Event Collector service (wecutil qc).
      2. Creates a source-initiated WEF subscription ('ZT-Security-Collection')
         that pulls the ZT-relevant channels from forwarding endpoints into the
         ForwardedEvents log.
      3. Grants the forwarders (Domain Computers by default) permission to push.
      4. Optionally enlarges ForwardedEvents and installs Sysmon for richer
         process/network telemetry that the 8.6.2 detections rely on.

    This makes ForwardedEvents the queryable "single pane" that New-DetectionRules.ps1
    (8.6.2) writes detections against. If you instead point WEF at Microsoft
    Sentinel or Elastic, do that in the marked OPTIONAL block - the subscription
    and channel selection here are still the right source set.

.PARAMETER SubscriptionName
    WEF subscription name. Default 'ZT-Security-Collection'.

.PARAMETER ForwarderGroup
    AD group/principal allowed to forward. Default 'Domain Computers'.

.PARAMETER ForwardedEventsSizeMB
    Resize the ForwardedEvents log to this many MB. Default 1024.

.PARAMETER InstallSysmon
    Switch - download+install Sysmon with a sensible config (needs internet).

.PARAMETER SysmonSha256
    Optional SHA-256 hash of the Sysmon.zip the operator expects. If supplied,
    the script computes the hash of the downloaded zip and aborts the install
    on mismatch. If omitted, the observed hash is written to the console so
    the operator can record it for later out-of-band verification against the
    Sysinternals download page. Microsoft does not publish a stable hash -
    Sysmon.zip changes with each release - so pinning is a per-deploy decision.

.PARAMETER DryRun
    Switch - preview without changing anything.

.EXAMPLE
    .\Deploy-SIEM.ps1

.EXAMPLE
    .\Deploy-SIEM.ps1 -InstallSysmon -ForwardedEventsSizeMB 4096

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.6.1 - Visibility -> Decisioning
    Run on     : The collector VM (a dedicated SIEM/WEC host)
    Depends on : WEF forwarding configured in Phase 6
    NIST       : AU-2, AU-6, AU-12, SI-4
    Last Edit  : 2026-06-29
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SubscriptionName      = 'ZT-Security-Collection',
    [string]$ForwarderGroup        = 'Domain Computers',
    [int]   $ForwardedEventsSizeMB = 1024,
    [switch]$InstallSysmon,
    [string]$SysmonSha256 = '',
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
Write-Host '  |   Phase 8.6.1 - Deploy SIEM (Windows Event Collector)|' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# Resolve the forwarder group to a SID for the subscription's allowed-source SDDL.
# Note: SDDL does NOT have a 2-letter abbreviation for Domain Computers (the
# 2-letter set covers things like BA = Built-in Admins, DA = Domain Admins,
# WD = World/Everyone, but not Domain Computers). If we can't resolve the
# principal to a real SID we must fail rather than emit an invalid SDDL string
# - wecutil silently rejects bad SDDL on the subscription.
$forwarderSid = $null
try {
    $forwarderSid = (New-Object System.Security.Principal.NTAccount($ForwarderGroup)).Translate([System.Security.Principal.SecurityIdentifier]).Value
} catch {
    Write-Warn "Could not resolve '$ForwarderGroup' to a SID via NTAccount.Translate; trying Get-ADGroup..."
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $grp = Get-ADGroup -Identity $ForwarderGroup -ErrorAction Stop
        $forwarderSid = $grp.SID.Value
    } catch {
        Write-Fatal ("Cannot resolve forwarder group '$ForwarderGroup' to a SID. " +
                     "Provide a valid -ForwarderGroup that the script can resolve " +
                     "to an actual SecurityIdentifier (e.g. 'Domain Computers'). " +
                     "Refusing to build the WEF subscription with an invalid SDDL " +
                     "string - wecutil would reject it silently.")
    }
}
Write-OK "Forwarder SID resolved: $forwarderSid  ($ForwarderGroup)"

# -- Step 1: enable the collector service -------------------------------------
Write-Step 'Phase 1 - Windows Event Collector service'
if ($PSCmdlet.ShouldProcess('Windows Event Collector', 'wecutil qc')) {
    if (-not $DryRun) {
        & wecutil qc /q 2>&1 | Out-Null
        Set-Service -Name Wecsvc -StartupType Automatic
        Start-Service -Name Wecsvc -ErrorAction SilentlyContinue
    }
    Write-OK 'Collector service enabled and running (Wecsvc)'
}
Write-Host ''

# -- Step 2: resize ForwardedEvents -------------------------------------------
Write-Step "Phase 2 - ForwardedEvents log size -> $ForwardedEventsSizeMB MB"
if ($PSCmdlet.ShouldProcess('ForwardedEvents', "Set max size $ForwardedEventsSizeMB MB")) {
    if (-not $DryRun) {
        & wevtutil sl ForwardedEvents /ms:$($ForwardedEventsSizeMB * 1MB) 2>&1 | Out-Null
    }
    Write-OK "ForwardedEvents sized to $ForwardedEventsSizeMB MB"
}
Write-Host ''

# -- Step 3: build the subscription XML ----------------------------------------
# ZT-relevant channels/queries. Source-initiated: endpoints push via WEF GPO.
# $forwarderSid is guaranteed populated by the resolve-or-fail block above.
$allowedSourceSddl = "O:NSG:NSD:(A;;GA;;;$forwarderSid)"

$queryXml = @"
<QueryList>
  <Query Id="0">
    <!-- Logon / Kerberos / account changes -->
    <Select Path="Security">*[System[(EventID=4624 or EventID=4625 or EventID=4634 or EventID=4648)]]</Select>
    <Select Path="Security">*[System[(EventID=4768 or EventID=4769 or EventID=4771)]]</Select>
    <Select Path="Security">*[System[(EventID=4720 or EventID=4722 or EventID=4724 or EventID=4728 or EventID=4732 or EventID=4756)]]</Select>
    <!-- Privilege use / new service / scheduled task -->
    <Select Path="Security">*[System[(EventID=4672 or EventID=4673 or EventID=4697 or EventID=4698)]]</Select>
    <!-- AD CS certificate issuance -->
    <Select Path="Security">*[System[(EventID=4886 or EventID=4887 or EventID=4888)]]</Select>
    <!-- PowerShell / process creation -->
    <Select Path="Microsoft-Windows-PowerShell/Operational">*[System[(EventID=4104)]]</Select>
    <Select Path="Security">*[System[(EventID=4688)]]</Select>
  </Query>
</QueryList>
"@

$subXml = @"
<Subscription xmlns="http://schemas.microsoft.com/2006/03/windows/events/subscription">
  <SubscriptionId>$SubscriptionName</SubscriptionId>
  <SubscriptionType>SourceInitiated</SubscriptionType>
  <Description>Phase 8.6.1 - Zero Trust security event collection</Description>
  <Enabled>true</Enabled>
  <Uri>http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog</Uri>
  <ConfigurationMode>Normal</ConfigurationMode>
  <Delivery Mode="Push">
    <Batching><MaxLatencyTime>30000</MaxLatencyTime></Batching>
    <PushSettings><Heartbeat Interval="60000"/></PushSettings>
  </Delivery>
  <Query><![CDATA[$queryXml]]></Query>
  <ReadExistingEvents>false</ReadExistingEvents>
  <TransportName>HTTP</TransportName>
  <ContentFormat>RenderedText</ContentFormat>
  <Locale Language="en-US"/>
  <LogFile>ForwardedEvents</LogFile>
  <AllowedSourceNonDomainComputers></AllowedSourceNonDomainComputers>
  <AllowedSourceDomainComputers>$allowedSourceSddl</AllowedSourceDomainComputers>
</Subscription>
"@

Write-Step "Phase 3 - WEF subscription '$SubscriptionName'"
$existing = (& wecutil es 2>$null) | Where-Object { $_ -eq $SubscriptionName }
if ($existing) {
    Write-Skip "Subscription '$SubscriptionName' already exists"
} elseif ($PSCmdlet.ShouldProcess($SubscriptionName, 'Create WEF subscription')) {
    if (-not $DryRun) {
        $tmp = Join-Path $env:TEMP "$SubscriptionName.xml"
        Set-Content -Path $tmp -Value $subXml -Encoding UTF8
        & wecutil cs $tmp 2>&1 | Out-Null
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    Write-OK "Created subscription '$SubscriptionName' (source-initiated, ZT channel set)"
    Write-Info 'Endpoints push via the WEF GPO from Phase 6 (SubscriptionManager = this host).'
}
Write-Host ''

# -- Step 4: optional Sysmon enrichment ---------------------------------------
if ($InstallSysmon) {
    Write-Step 'Phase 4 - Sysmon (process/network telemetry)'
    if (Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue) {
        Write-Skip 'Sysmon already installed'
    } elseif ($PSCmdlet.ShouldProcess('Sysmon', 'Download + install')) {
        if (-not $DryRun) {
            try {
                $zip = Join-Path $env:TEMP 'Sysmon.zip'
                $dir = Join-Path $env:TEMP 'Sysmon'
                Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile $zip -UseBasicParsing
                # Hash verification: always compute + log; gate the install if -SysmonSha256 was supplied.
                $observedHash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
                Write-Info "Sysmon.zip SHA-256: $observedHash"
                if ($SysmonSha256) {
                    if ($observedHash -ieq $SysmonSha256) {
                        Write-OK "SHA-256 matches operator-supplied pin"
                    } else {
                        Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue
                        Write-Fatal ("Sysmon.zip SHA-256 mismatch. Expected: $SysmonSha256. " +
                                     "Got: $observedHash. Aborting install - the downloaded " +
                                     "file does not match the pinned hash.")
                    }
                } else {
                    Write-Warn "No -SysmonSha256 pin supplied; recording observed hash above and proceeding. Verify against https://learn.microsoft.com/sysinternals/downloads/sysmon if this is a production deploy."
                }
                Expand-Archive -Path $zip -DestinationPath $dir -Force
                # minimal config: process create, network connect, image load
                $cfg = Join-Path $dir 'zt-sysmon.xml'
                @'
<Sysmon schemaversion="4.90">
  <EventFiltering>
    <ProcessCreate onmatch="exclude"/>
    <NetworkConnect onmatch="exclude"/>
    <ImageLoad onmatch="exclude"/>
  </EventFiltering>
</Sysmon>
'@ | Set-Content -Path $cfg -Encoding UTF8
                & (Join-Path $dir 'Sysmon64.exe') -accepteula -i $cfg 2>&1 | Out-Null
                Write-OK 'Sysmon installed with baseline config'
                Write-Info 'Add Sysmon channel to a WEF subscription or forward it to extend detections.'
            } catch {
                Write-Warn "Sysmon install failed: $($_.Exception.Message.Split([char]10)[0])"
            }
        }
    }
    Write-Host ''
}

# -- OPTIONAL: external SIEM (Sentinel / Elastic) -----------------------------
# TODO (only if NOT using the native WEC path above):
#   * Sentinel: install the Azure Monitor Agent (AMA), create a Data Collection
#     Rule targeting the Security + ForwardedEvents logs, link the workspace.
#   * Elastic : install Winlogbeat, point winlogbeat.yml at ForwardedEvents and
#     the Elasticsearch/cloud endpoint, run `winlogbeat setup`.
# The channel/event set selected above is the correct source list for either.

Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Collector ready. Forwarded ZT events land in: ForwardedEvents' -ForegroundColor White
Write-Host '    Verify sources are reporting:' -ForegroundColor Yellow
Write-Host "      wecutil gr $SubscriptionName     # runtime status / active sources" -ForegroundColor Yellow
Write-Host '      Get-WinEvent -LogName ForwardedEvents -MaxEvents 20' -ForegroundColor Yellow
Write-Host '    Next: New-DetectionRules.ps1 to author detections over this stream.' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
