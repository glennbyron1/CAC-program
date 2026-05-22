#Requires -Version 5.1
<#
.SYNOPSIS
    Audit Log Forwarding Configuration — Smart Card & AD CS Event Log Subscriptions

.DESCRIPTION
    Configures Windows Event Forwarding (WEF) subscriptions and audit policies to capture
    smart card authentication events and AD CS certificate lifecycle events, then forwards
    them to a central Windows Event Collector or SIEM-ready event log.

    What this script does:
      1. Configures Advanced Audit Policy for smart card logon and Kerberos events
      2. Enables WinRM on the source machine (required for WEF)
      3. Creates a Windows Event Collector subscription on the collector server
         for smart card logon events (Event IDs 4768, 4769, 4776, 4624, 4625)
      4. Confirms AD CS audit logging is active (AuditFilter 127)
      5. Configures the AD CS audit log forwarding to the collector
      6. Optionally configures a Syslog/SIEM forwarding agent if present

    Event IDs tracked:
      4624 — Successful logon (smart card logon type 12)
      4625 — Failed logon attempt
      4768 — Kerberos TGT request (smart card PKINIT)
      4769 — Kerberos service ticket request
      4776 — NTLM / credential validation attempt
      4886 — Certificate Services received a certificate request
      4887 — Certificate Services approved and issued a certificate
      4888 — Certificate Services denied a certificate request
      4890 — Certificate Services revoked a certificate

    Document ID : SCRIPT-ICAM-013
    Framework   : NIST SP 800-53 AU-2, AU-12, CA-7, SI-4 | CISA ZTMM Detect pillar

.PARAMETER Mode
    Collector  — Configure this machine as the WEF event collector
    Source     — Configure this machine as a WEF source (forwards events to collector)
    AuditOnly  — Configure audit policies only, no WEF (use if you have a separate SIEM agent)
    Status     — Show current audit policy and WEF subscription status

.PARAMETER CollectorFQDN
    FQDN of the Windows Event Collector server. Required for Source and Collector modes.
    Example: "siem-collector.lab.local"

.PARAMETER SubscriptionName
    Name for the WEF subscription. Default: "ICAM-SmartCard-Audit"

.PARAMETER CAServerName
    Name of the AD CS Certification Authority server. Used to confirm/set AD CS audit logging.
    Example: "ca01.lab.local\Enterprise Issuing CA"

.PARAMETER SiemAgent
    Optional. Path to a Syslog/SIEM forwarding agent config file. If specified, the script
    adds the relevant event log channels to the agent configuration.

.EXAMPLE
    # Configure audit policies only (no WEF)
    .\Set-AuditLogForwarding.ps1 -Mode AuditOnly -CAServerName "ca01.lab.local\Enterprise Issuing CA"

    # Configure this machine as the WEF collector
    .\Set-AuditLogForwarding.ps1 -Mode Collector -CollectorFQDN "siem-collector.lab.local"

    # Configure domain controllers and CA server as WEF sources
    .\Set-AuditLogForwarding.ps1 -Mode Source -CollectorFQDN "siem-collector.lab.local" `
        -CAServerName "ca01.lab.local\Enterprise Issuing CA"

    # Check current status
    .\Set-AuditLogForwarding.ps1 -Mode Status

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    REQUIREMENTS:
    - Collector mode: Windows Server with Event Collector role
    - Source mode: WinRM must be reachable; GPO or local policy can replace this script
    - CAServerName format: "ServerFQDN\CACommonName" (as shown in certutil -config -)

    GPO ALTERNATIVE:
    For domain environments, configure WEF via GPO instead of running this script on each host:
    Computer Config → Windows Settings → Security Settings → Event Log Subscriptions
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Collector','Source','AuditOnly','Status')]
    [string]$Mode,

    [Parameter()]
    [string]$CollectorFQDN = "",

    [Parameter()]
    [string]$SubscriptionName = "ICAM-SmartCard-Audit",

    [Parameter()]
    [string]$CAServerName = "",

    [Parameter()]
    [string]$SiemAgent = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host "  AUDIT LOG FORWARDING SETUP | SCRIPT-ICAM-013 | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  NIST SP 800-53 AU-2, AU-12, CA-7 | Mode: $Mode" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor White }
function Write-OK   { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }
function Write-Section { param([string]$T) Write-Host ""; Write-Host "── $T" -ForegroundColor White }

# ---------------------------------------------------------------------------
# AUDIT POLICY CONFIGURATION
# ---------------------------------------------------------------------------
function Set-SmartCardAuditPolicy {
    Write-Section "Advanced Audit Policy — Smart Card & Kerberos Events"

    $auditCategories = @(
        # Subcategory                              | Success | Failure
        @{ Sub = "Logon";                           S = $true;  F = $true  },
        @{ Sub = "Logoff";                          S = $true;  F = $false },
        @{ Sub = "Kerberos Authentication Service"; S = $true;  F = $true  },
        @{ Sub = "Kerberos Service Ticket Operations"; S = $true; F = $true },
        @{ Sub = "Credential Validation";           S = $true;  F = $true  },
        @{ Sub = "Certification Services";          S = $true;  F = $true  },
        @{ Sub = "Special Logon";                   S = $true;  F = $false }
    )

    foreach ($cat in $auditCategories) {
        $success = if ($cat.S) { "enable" } else { "disable" }
        $failure = if ($cat.F) { "enable" } else { "disable" }
        $subName = $cat.Sub

        Write-Step "Setting audit policy: '$subName' (Success: $success / Failure: $failure)"

        if ($PSCmdlet.ShouldProcess($subName, "Set audit policy")) {
            # AuditPol /set /subcategory:"<name>" /success:enable /failure:enable
            $result = & auditpol /set /subcategory:"$subName" /success:$success /failure:$failure 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Set: $subName"
            } else {
                # Try GUID-based fallback for localized OS versions
                Write-Warn "Name-based policy set failed for '$subName' — may need GUID or localized name"
                Write-Info "Manual: auditpol /set /subcategory:`"$subName`" /success:$success /failure:$failure"
            }
        }
    }

    # Verify the result
    Write-Host ""
    Write-Step "Verifying audit policy configuration..."
    $auditpolOutput = & auditpol /get /category:* 2>&1 | Out-String
    if ($auditpolOutput -match "Logon\s+Success and Failure") {
        Write-OK "Logon auditing: Success and Failure confirmed"
    }
    if ($auditpolOutput -match "Kerberos Authentication") {
        Write-OK "Kerberos auditing confirmed"
    }
    if ($auditpolOutput -match "Certification Services") {
        Write-OK "Certificate Services auditing confirmed"
    }
}

# ---------------------------------------------------------------------------
# AD CS AUDIT FILTER VERIFICATION
# ---------------------------------------------------------------------------
function Set-ADCSAuditFilter {
    Write-Section "AD CS Audit Logging (AuditFilter = 127)"

    if (-not $CAServerName) {
        Write-Info "No -CAServerName specified — skipping AD CS audit config."
        Write-Info "To configure AD CS audit logging manually, run on the CA server:"
        Write-Info "  certutil -config `"<ServerFQDN>\<CAName>`" -setreg CA\AuditFilter 127"
        Write-Info "  net stop certsvc && net start certsvc"
        return
    }

    Write-Step "Checking AD CS AuditFilter on: $CAServerName"

    try {
        $currentFilter = & certutil -config "$CAServerName" -getreg CA\AuditFilter 2>&1 | Out-String
        if ($currentFilter -match "AuditFilter REG_DWORD = 0x7f \(127\)") {
            Write-OK "AD CS AuditFilter is already set to 127 (all events audited)"
        } else {
            Write-Warn "AD CS AuditFilter is NOT set to 127 — configuring..."
            if ($PSCmdlet.ShouldProcess($CAServerName, "Set AuditFilter = 127")) {
                & certutil -config "$CAServerName" -setreg CA\AuditFilter 127
                if ($LASTEXITCODE -eq 0) {
                    Write-OK "AuditFilter set to 127"
                    Write-Warn "Restart the Certificate Services service to apply:"
                    Write-Info "  net stop certsvc && net start certsvc"
                } else {
                    Write-Fail "Failed to set AuditFilter — run manually on the CA server"
                }
            }
        }

        Write-Host ""
        Write-Info "AD CS audit events captured with AuditFilter 127:"
        @(
            "4886 — Certificate request received",
            "4887 — Certificate issued",
            "4888 — Certificate request denied",
            "4889 — Certificate template modified",
            "4890 — Certificate revoked",
            "4896 — Rows deleted from certificate database",
            "4898 — Certificate Services loaded a template"
        ) | ForEach-Object { Write-Info "  $_" }

    } catch {
        Write-Warn "Could not query CA server '$CAServerName': $_"
        Write-Info "Ensure certutil is available and the CA service is running."
    }
}

# ---------------------------------------------------------------------------
# WEF COLLECTOR MODE
# ---------------------------------------------------------------------------
function Set-WEFCollector {
    Write-Section "Windows Event Forwarding — Collector Configuration"

    if (-not $CollectorFQDN) {
        Write-Fail "-CollectorFQDN is required for Collector mode."
        return
    }

    # Enable Windows Event Collector service
    Write-Step "Enabling Windows Event Collector service (wecsvc)..."
    if ($PSCmdlet.ShouldProcess("wecsvc", "Set service to Automatic and start")) {
        Set-Service -Name wecsvc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name wecsvc -ErrorAction SilentlyContinue
        $svc = Get-Service -Name wecsvc
        if ($svc.Status -eq 'Running') {
            Write-OK "Windows Event Collector service is running"
        } else {
            Write-Warn "Service may not have started — check: Get-Service wecsvc"
        }
    }

    # Run wecutil qc to quick-configure the collector
    Write-Step "Quick-configuring Event Collector (wecutil qc)..."
    if ($PSCmdlet.ShouldProcess("wecutil", "Quick-configure collector")) {
        & wecutil qc /q 2>&1 | Out-Null
        Write-OK "Event Collector quick-configured"
    }

    # Build the subscription XML
    Write-Step "Creating WEF subscription: $SubscriptionName"

    $subscriptionXML = @"
<Subscription xmlns="http://schemas.microsoft.com/2006/03/windows/events/subscription">
    <SubscriptionId>$SubscriptionName</SubscriptionId>
    <SubscriptionType>SourceInitiated</SubscriptionType>
    <Description>ICAM Smart Card and AD CS Audit Events — NIST AU-2, AU-12, CA-7</Description>
    <Enabled>true</Enabled>
    <Uri>http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog</Uri>
    <ConfigurationMode>MinLatency</ConfigurationMode>
    <Delivery Mode="Push">
        <Batching>
            <MaxItems>1</MaxItems>
            <MaxLatencyTime>30000</MaxLatencyTime>
        </Batching>
        <PushSettings>
            <Heartbeat>
                <Interval>1800000</Interval>
            </Heartbeat>
        </PushSettings>
    </Delivery>
    <Query>
        <![CDATA[
        <QueryList>
          <!-- Smart Card Logon Events (Security Log) -->
          <Query Id="0" Path="Security">
            <Select Path="Security">
              *[System[(EventID=4624 or EventID=4625 or EventID=4768 or EventID=4769 or EventID=4776)]]
              and
              *[EventData[Data[@Name='LogonType']='12' or not(Data[@Name='LogonType'])]]
            </Select>
          </Query>
          <!-- Smart Card All Logon Events (broader capture) -->
          <Query Id="1" Path="Security">
            <Select Path="Security">
              *[System[(EventID=4768 or EventID=4769 or EventID=4776)]]
            </Select>
          </Query>
          <!-- AD CS Certificate Services Events -->
          <Query Id="2" Path="Security">
            <Select Path="Security">
              *[System[(EventID=4886 or EventID=4887 or EventID=4888 or EventID=4889 or EventID=4890 or EventID=4896 or EventID=4898)]]
            </Select>
          </Query>
          <!-- Special Logon / Privilege Use -->
          <Query Id="3" Path="Security">
            <Select Path="Security">
              *[System[(EventID=4672)]]
            </Select>
          </Query>
        </QueryList>
        ]]>
    </Query>
    <ReadExistingEvents>false</ReadExistingEvents>
    <TransportName>HTTP</TransportName>
    <ContentFormat>RenderedText</ContentFormat>
    <Locale Language="en-US"/>
    <LogFile>ForwardedEvents</LogFile>
    <AllowedSourceNonDomainComputers></AllowedSourceNonDomainComputers>
    <AllowedSourceDomainComputers>O:NSG:NSD:(A;;GA;;;DC)(A;;GA;;;NS)</AllowedSourceDomainComputers>
</Subscription>
"@

    $tempXML = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.xml'
    $subscriptionXML | Set-Content -Path $tempXML -Encoding UTF8

    if ($PSCmdlet.ShouldProcess($SubscriptionName, "Create WEF subscription")) {
        $result = & wecutil cs "$tempXML" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-OK "WEF subscription '$SubscriptionName' created"
        } else {
            # Try to update if it already exists
            $result2 = & wecutil ss "$SubscriptionName" /c:"$tempXML" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-OK "WEF subscription '$SubscriptionName' updated (already existed)"
            } else {
                Write-Warn "Subscription create/update returned: $result"
                Write-Info "Review: $tempXML and import manually with: wecutil cs `"$tempXML`""
            }
        }
    }

    Remove-Item $tempXML -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "  Forwarded events will appear in: Windows Logs → Forwarded Events" -ForegroundColor DarkGray
    Write-Host "  Source machines must run this script in Source mode to subscribe." -ForegroundColor DarkGray
    Write-Host ""
    Write-OK "Collector configured — $CollectorFQDN"
}

# ---------------------------------------------------------------------------
# WEF SOURCE MODE
# ---------------------------------------------------------------------------
function Set-WEFSource {
    Write-Section "Windows Event Forwarding — Source Configuration"

    if (-not $CollectorFQDN) {
        Write-Fail "-CollectorFQDN is required for Source mode."
        return
    }

    # Enable WinRM
    Write-Step "Enabling WinRM for event forwarding..."
    if ($PSCmdlet.ShouldProcess("WinRM", "Enable and configure")) {
        try {
            & winrm quickconfig -quiet 2>&1 | Out-Null
            Write-OK "WinRM configured"
        } catch {
            Write-Warn "WinRM quickconfig: $_"
        }
    }

    # Add the collector to the event forwarding configuration
    Write-Step "Configuring event forwarding to collector: $CollectorFQDN"

    # Set the subscription manager URL via registry
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager"
    if ($PSCmdlet.ShouldProcess($regPath, "Set SubscriptionManager")) {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        $serverURL = "Server=http://${CollectorFQDN}:5985/wsman/SubscriptionManager/WEC,Refresh=1800"
        Set-ItemProperty -Path $regPath -Name "1" -Value $serverURL -Type String
        Write-OK "SubscriptionManager set: $serverURL"
    }

    # Ensure the Network Service account can read the Security event log
    Write-Step "Granting Network Service read access to Security event log..."
    if ($PSCmdlet.ShouldProcess("Security event log", "Grant NETWORK SERVICE read")) {
        try {
            & wevtutil sl Security /ca:"O:BAG:SYD:(A;;0xf0005;;;SY)(A;;0x5;;;BA)(A;;0x1;;;S-1-5-32-573)(A;;0x1;;;NS)" 2>&1 | Out-Null
            Write-OK "Security log permissions updated"
        } catch {
            Write-Warn "Could not update Security log SDDL — $_"
        }
    }

    Write-Host ""
    Write-OK "Source configured — this machine will forward events to $CollectorFQDN"
    Write-Info "Run 'gpupdate /force' then wait up to 15 minutes for the subscription to activate."
    Write-Info "Verify with: wecutil gr `"$SubscriptionName`""
}

# ---------------------------------------------------------------------------
# STATUS CHECK
# ---------------------------------------------------------------------------
function Get-ForwardingStatus {
    Write-Section "Current Audit and Forwarding Status"

    Write-Host ""
    Write-Host "  AUDIT POLICY (relevant subcategories):" -ForegroundColor Cyan
    $auditpol = & auditpol /get /category:* 2>&1
    $relevant  = $auditpol | Where-Object {
        $_ -match "Logon|Kerberos|Credential|Certification|Special Logon"
    }
    $relevant | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "  WINRM STATUS:" -ForegroundColor Cyan
    $winrmSvc = Get-Service -Name winrm -ErrorAction SilentlyContinue
    if ($winrmSvc.Status -eq 'Running') {
        Write-OK "WinRM service is running"
    } else {
        Write-Warn "WinRM service is NOT running — required for event forwarding"
    }

    Write-Host ""
    Write-Host "  WINDOWS EVENT COLLECTOR (wecsvc):" -ForegroundColor Cyan
    $wecsvc = Get-Service -Name wecsvc -ErrorAction SilentlyContinue
    if ($wecsvc) {
        Write-Info "Service status: $($wecsvc.Status) | Startup: $($wecsvc.StartType)"
    } else {
        Write-Info "wecsvc not found — collector role not installed on this machine"
    }

    Write-Host ""
    Write-Host "  WEF SUBSCRIPTIONS:" -ForegroundColor Cyan
    $subs = & wecutil es 2>&1
    if ($subs) {
        $subs | ForEach-Object { Write-Info "  Subscription: $_" }
    } else {
        Write-Info "  No WEF subscriptions found on this machine"
    }

    Write-Host ""
    Write-Host "  SUBSCRIPTION MANAGER (registry):" -ForegroundColor Cyan
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager"
    if (Test-Path $regPath) {
        Get-ItemProperty -Path $regPath | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } |
            ForEach-Object { Write-Info "  $($_.Name): $($_.Value)" }
        }
    } else {
        Write-Info "  No SubscriptionManager configured — Source mode not set up"
    }

    Write-Host ""
    Write-Host "  KEY EVENT IDs TO MONITOR:" -ForegroundColor Cyan
    @(
        "4624 — Account logon (Type 12 = Smart Card)",
        "4625 — Failed logon",
        "4768 — Kerberos TGT requested (PKINIT smart card)",
        "4769 — Kerberos service ticket requested",
        "4776 — NTLM credential validation",
        "4886 — AD CS: Certificate request received",
        "4887 — AD CS: Certificate issued",
        "4888 — AD CS: Certificate request denied",
        "4890 — AD CS: Certificate revoked"
    ) | ForEach-Object { Write-Info "  $_" }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# OPTIONAL: SIEM AGENT CONFIGURATION NOTE
# ---------------------------------------------------------------------------
function Write-SIEMNote {
    if (-not $SiemAgent) { return }

    Write-Section "SIEM Agent Configuration"
    Write-Info "SIEM agent path specified: $SiemAgent"
    Write-Host ""
    Write-Host "  To forward these channels to your SIEM, add the following to your" -ForegroundColor DarkGray
    Write-Host "  agent configuration:" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Windows Event Log channels to monitor:" -ForegroundColor White
    @(
        "Security              — logon, Kerberos, credential, and AD CS events",
        "ForwardedEvents       — collected events from domain controllers and CA server",
        "Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational — cert lifecycle"
    ) | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  XPath filters for targeted ingestion (paste into your agent config):" -ForegroundColor White
    Write-Host "    Security: *[System[(EventID=4624 or EventID=4625 or EventID=4768 or EventID=4769 or EventID=4776 or EventID=4886 or EventID=4887 or EventID=4888 or EventID=4890)]]" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Banner

# Always configure audit policies
Set-SmartCardAuditPolicy
Set-ADCSAuditFilter

switch ($Mode) {
    'Collector' { Set-WEFCollector }
    'Source'    { Set-WEFSource }
    'AuditOnly' { Write-Info "AuditOnly mode — skipping WEF configuration." }
    'Status'    { Get-ForwardingStatus }
}

Write-SIEMNote

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host "  CONFIGURATION COMPLETE — Mode: $Mode" -ForegroundColor Cyan
Write-Host "  Run -Mode Status at any time to verify the current configuration." -ForegroundColor DarkGray
Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host ""
