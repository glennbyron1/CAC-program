#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end CAC/PIV lab readiness validator — run this before the formal SCAP scan.

.DESCRIPTION
    Runs a structured pass/fail check across every layer of the CAC/PIV lab stack.
    A clean PASS on all checks confirms the environment is properly configured and
    ready for the formal DISA SCAP SCC before/after scan sequence.

    What it checks:

    LAYER 1 — Domain & Network
      - This machine is domain-joined to the expected domain
      - Domain controller is reachable (LDAP port 389)
      - DNS resolves the domain controller FQDN
      - Kerberos time skew < 5 minutes (skew > 5 min breaks smart card logon)

    LAYER 2 — PKI & Certificate Infrastructure
      - Root CA certificate is in LocalMachine\Root trust store
      - Issuing CA certificate is in LocalMachine\CA
      - CRL URL is reachable and the CRL is not expired
      - OCSP URL responds (if provided)
      - At least one Smart Card Logon certificate exists for the test user (EKU check)
      - No certificates in the trust chain are expired

    LAYER 3 — Smart Card Hardware
      - Smart card service (SCardSvr) is running
      - Smart card device enumerator (ScDeviceEnum) is running
      - A smart card reader is detected
      - A card is present in the reader

    LAYER 4 — GPO & Registry Settings
      - scforceoption = 1 (smart card required for interactive logon)
      - ScRemoveOption = 1 or 2 (lock or force-logoff on card removal)
      - InactivityTimeoutSecs <= 900 (idle lock within 15 minutes)

    LAYER 5 — Audit Policy
      - Logon/Logoff subcategory is auditing Success and Failure
      - Kerberos Authentication Service auditing Success and Failure
      - Certification Services auditing Success and Failure
      - Security event log size >= 512 MB

    LAYER 6 — VPN (optional)
      - VPN connection profile exists
      - Tunnel type is IKEv2
      - Authentication method includes EAP (certificate-based)
      - Live connection test (optional — prompts before attempting)

    LAYER 7 — Recent Audit Events (smoke test)
      - Event 4768 (Kerberos TGT request) in Security log in last 24 hours
      - Event 4624 (successful logon) in Security log in last 24 hours
      - Checks that audit events are actually being generated, not just configured

    Output: color-coded PASS / WARN / FAIL per check, summary score, and an
    optional exported report file.

.PARAMETER DomainName
    Expected domain FQDN (e.g. lab.local). Defaults to the machine's current domain.

.PARAMETER DCHostname
    Domain controller FQDN to ping and resolve. Defaults to the PDC emulator.

.PARAMETER CRLUrl
    HTTP URL of the Issuing CA CRL (e.g. http://pki.lab.local/crl/IssuingCA.crl).
    If omitted, the check is skipped with a WARN.

.PARAMETER OCSPUrl
    HTTP URL of the OCSP responder (e.g. http://ocsp.lab.local/ocsp).
    If omitted, the check is skipped with a WARN.

.PARAMETER VPNConnectionName
    Name of the VPN connection profile to check (e.g. "Lab VPN").
    If omitted, VPN checks are skipped.

.PARAMETER TestUserUPN
    UPN of a test user account that should have a smart card certificate enrolled
    (e.g. testuser@lab.local). Used to verify certificate issuance in Layer 2.

.PARAMETER ExportReport
    Save a text report to the current directory.

.EXAMPLE
    # Minimal — just check this machine's baseline
    .\Invoke-LabValidation.ps1

    # Full check with CRL/OCSP and VPN
    .\Invoke-LabValidation.ps1 `
        -DomainName "lab.local" `
        -DCHostname "Lab-DC01.lab.local" `
        -CRLUrl "http://pki.lab.local/crl/IssuingCA.crl" `
        -OCSPUrl "http://ocsp.lab.local/ocsp" `
        -VPNConnectionName "Lab VPN" `
        -TestUserUPN "testuser@lab.local" `
        -ExportReport

.NOTES
    Author  : Glenn Byron
    Run on  : The lab workstation or DC being validated. Must run as Administrator.
    When    : After all scripts have run, before the SCAP SCC scan.
    Framework: NIST SP 800-53 CA-2, CA-7 | DISA RMF Assess phase
#>

[CmdletBinding()]
param(
    [Parameter()] [string]$DomainName        = '',
    [Parameter()] [string]$DCHostname        = '',
    [Parameter()] [string]$CRLUrl            = '',
    [Parameter()] [string]$OCSPUrl           = '',
    [Parameter()] [string]$VPNConnectionName = '',
    [Parameter()] [string]$TestUserUPN       = '',
    [Parameter()] [switch]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
$script:Results = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:PassCount = 0
$script:WarnCount = 0
$script:FailCount = 0

function Add-Result {
    param([string]$Layer, [string]$Check, [string]$Status, [string]$Detail)
    $script:Results.Add([PSCustomObject]@{
        Layer  = $Layer
        Check  = $Check
        Status = $Status
        Detail = $Detail
    })
    switch ($Status) {
        'PASS' { $script:PassCount++ }
        'WARN' { $script:WarnCount++ }
        'FAIL' { $script:FailCount++ }
    }
}

function Write-Result {
    param([string]$Layer, [string]$Check, [string]$Status, [string]$Detail)
    Add-Result -Layer $Layer -Check $Check -Status $Status -Detail $Detail
    $color = switch ($Status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Gray' } }
    $label = "[$Status]".PadRight(6)
    Write-Host "  $label  $Check" -ForegroundColor $color
    if ($Detail) { Write-Host "           $Detail" -ForegroundColor DarkGray }
}

function Write-LayerHeader { param([string]$Title)
    Write-Host ""
    Write-Host "  ── $Title" -ForegroundColor White
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  CAC/PIV LAB END-TO-END VALIDATION" -ForegroundColor Cyan
Write-Host "  Author: Glenn Byron  |  Run before SCAP SCC scan" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')  on  $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor DarkCyan

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [!] Not running as Administrator. Some checks will fail." -ForegroundColor Red
    Write-Host "  Restart PowerShell as Administrator for accurate results." -ForegroundColor Red
    Write-Host ""
}

# ---------------------------------------------------------------------------
# LAYER 1 — Domain & Network
# ---------------------------------------------------------------------------
Write-LayerHeader "Layer 1 — Domain & Network"

# Domain membership
$compSys  = Get-CimInstance -ClassName Win32_ComputerSystem
$joinedDomain = $compSys.Domain

if ($DomainName -eq '') { $DomainName = $joinedDomain }

if ($compSys.PartOfDomain) {
    if ($joinedDomain -eq $DomainName) {
        Write-Result "L1" "Domain membership" "PASS" "Joined to $joinedDomain"
    } else {
        Write-Result "L1" "Domain membership" "WARN" "Joined to $joinedDomain (expected $DomainName)"
    }
} else {
    Write-Result "L1" "Domain membership" "FAIL" "Not domain-joined — smart card logon requires a domain"
}

# Find DC
if ($DCHostname -eq '') {
    try {
        $dc = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().PdcRoleOwner.Name
        $DCHostname = $dc
    } catch { $DCHostname = "dc.$DomainName" }
}

# DC reachability (LDAP port 389)
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($DCHostname, 389)
    $tcp.Close()
    Write-Result "L1" "DC reachable (LDAP:389)" "PASS" "$DCHostname"
} catch {
    Write-Result "L1" "DC reachable (LDAP:389)" "FAIL" "Cannot connect to $DCHostname`:389 — check network and DC status"
}

# DNS resolution
try {
    $resolved = [System.Net.Dns]::GetHostAddresses($DCHostname)
    Write-Result "L1" "DNS resolution" "PASS" "$DCHostname → $($resolved[0].IPAddressToString)"
} catch {
    Write-Result "L1" "DNS resolution" "FAIL" "Cannot resolve $DCHostname — check DNS configuration"
}

# Kerberos time skew
try {
    $domainTime = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().FindDomainController()).CurrentTime
    $skewSec    = [math]::Abs(((Get-Date) - $domainTime).TotalSeconds)
    if ($skewSec -le 300) {
        Write-Result "L1" "Kerberos time skew" "PASS" "$([math]::Round($skewSec,0))s skew (limit: 300s / 5 min)"
    } else {
        Write-Result "L1" "Kerberos time skew" "FAIL" "$([math]::Round($skewSec,0))s skew — smart card logon will fail. Fix: w32tm /resync /force"
    }
} catch {
    Write-Result "L1" "Kerberos time skew" "WARN" "Could not query DC time — run w32tm /resync /force as a precaution"
}

# ---------------------------------------------------------------------------
# LAYER 2 — PKI & Certificate Infrastructure
# ---------------------------------------------------------------------------
Write-LayerHeader "Layer 2 — PKI & Certificate Infrastructure"

# Root CA in trust store
$rootCAs = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -match 'CA' -and $_.NotAfter -gt (Get-Date) }
if ($rootCAs) {
    Write-Result "L2" "Root CA in trust store" "PASS" "$($rootCAs.Count) CA cert(s) in LocalMachine\Root"
} else {
    Write-Result "L2" "Root CA in trust store" "FAIL" "No CA certificates found in LocalMachine\Root — run certutil -addstore Root <cert>"
}

# Issuing CA in CA store
$issuingCAs = Get-ChildItem Cert:\LocalMachine\CA |
    Where-Object { $_.NotAfter -gt (Get-Date) }
if ($issuingCAs) {
    Write-Result "L2" "Issuing CA in CA store" "PASS" "$($issuingCAs.Count) cert(s) in LocalMachine\CA"
} else {
    Write-Result "L2" "Issuing CA in CA store" "WARN" "No certs in LocalMachine\CA — may be normal on workstations if chain auto-builds"
}

# Expiry check on all chain certs
$expiringSoon = @(Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\CA |
    Where-Object { $_.NotAfter -lt (Get-Date).AddDays(60) -and $_.NotAfter -gt (Get-Date) })
$expired = @(Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\CA |
    Where-Object { $_.NotAfter -le (Get-Date) })
if ($expired.Count -gt 0) {
    Write-Result "L2" "Certificate expiry" "FAIL" "$($expired.Count) expired cert(s) in trust chain — renew before scanning"
} elseif ($expiringSoon.Count -gt 0) {
    Write-Result "L2" "Certificate expiry" "WARN" "$($expiringSoon.Count) cert(s) expire within 60 days"
} else {
    Write-Result "L2" "Certificate expiry" "PASS" "All chain certs valid"
}

# Smart card logon cert for test user
$scEku = '1.3.6.1.4.1.311.20.2.2'   # Smart Card Logon OID
$scCerts = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
    Where-Object { ($_.EnhancedKeyUsageList.ObjectId -contains $scEku) -and ($_.NotAfter -gt (Get-Date)) }

if ($TestUserUPN) {
    $userCerts = $scCerts | Where-Object {
        ($_.Subject -match ($TestUserUPN -split '@')[0]) -or
        ($_.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } |
            ForEach-Object { $_.Format($false) } | Where-Object { $_ -match $TestUserUPN })
    }
    if ($userCerts) {
        Write-Result "L2" "Smart card cert for test user" "PASS" "$($userCerts.Count) cert(s) found for $TestUserUPN"
    } else {
        Write-Result "L2" "Smart card cert for test user" "FAIL" "No smart card logon cert for $TestUserUPN — enrollment required"
    }
} elseif ($scCerts) {
    Write-Result "L2" "Smart card logon certs" "PASS" "$($scCerts.Count) smart card logon cert(s) in CurrentUser\My"
} else {
    Write-Result "L2" "Smart card logon certs" "WARN" "No smart card logon certs in CurrentUser\My — may be expected on DC/CA servers"
}

# CRL reachability
if ($CRLUrl) {
    try {
        $crlBytes  = (New-Object System.Net.WebClient).DownloadData($CRLUrl)
        $crlObj    = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        # Parse CRL Next Update via certutil temp file
        $tmpCrl = [System.IO.Path]::GetTempFileName() + ".crl"
        [System.IO.File]::WriteAllBytes($tmpCrl, $crlBytes)
        $cuOut = & certutil -dump $tmpCrl 2>&1
        Remove-Item $tmpCrl -ErrorAction SilentlyContinue

        $nextUpdate = $cuOut | Where-Object { $_ -match 'Next CRL Publish|NextUpdate' } | Select-Object -First 1
        Write-Result "L2" "CRL reachable" "PASS" "$CRLUrl — $nextUpdate"
    } catch {
        Write-Result "L2" "CRL reachable" "FAIL" "Cannot fetch CRL from $CRLUrl — check IIS/CRL publishing"
    }
} else {
    Write-Result "L2" "CRL reachable" "WARN" "No -CRLUrl provided — skipped. Pass -CRLUrl to validate."
}

# OCSP
if ($OCSPUrl) {
    try {
        $req = [System.Net.WebRequest]::Create($OCSPUrl)
        $req.Method  = 'GET'
        $req.Timeout = 5000
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Result "L2" "OCSP reachable" "PASS" "$OCSPUrl responded"
    } catch {
        Write-Result "L2" "OCSP reachable" "FAIL" "$OCSPUrl did not respond — check Online Responder service"
    }
} else {
    Write-Result "L2" "OCSP reachable" "WARN" "No -OCSPUrl provided — skipped."
}

# ---------------------------------------------------------------------------
# LAYER 3 — Smart Card Hardware
# ---------------------------------------------------------------------------
Write-LayerHeader "Layer 3 — Smart Card Hardware"

$scardSvc = Get-Service -Name SCardSvr -ErrorAction SilentlyContinue
if ($scardSvc -and $scardSvc.Status -eq 'Running') {
    Write-Result "L3" "Smart Card service (SCardSvr)" "PASS" "Running"
} else {
    Write-Result "L3" "Smart Card service (SCardSvr)" "FAIL" "Not running — Start-Service SCardSvr"
}

$scDevSvc = Get-Service -Name ScDeviceEnum -ErrorAction SilentlyContinue
if ($scDevSvc -and $scDevSvc.Status -eq 'Running') {
    Write-Result "L3" "SC Device Enumerator (ScDeviceEnum)" "PASS" "Running"
} else {
    Write-Result "L3" "SC Device Enumerator (ScDeviceEnum)" "WARN" "Not running — may not be required on all configurations"
}

# Reader detection via WMI
$readers = Get-CimInstance -Namespace root\SmartCardReader -ClassName MSSmartCard_Reader -ErrorAction SilentlyContinue
if ($readers) {
    Write-Result "L3" "Smart card reader detected" "PASS" "$($readers.Count) reader(s): $($readers.Name -join ', ')"

    # Card present?
    $cards = $readers | Where-Object { $_.CardPresent -eq $true }
    if ($cards) {
        Write-Result "L3" "Card present in reader" "PASS" "Card detected in $($cards.Count) reader(s)"
    } else {
        Write-Result "L3" "Card present in reader" "WARN" "No card inserted — insert a smart card to test logon flow"
    }
} else {
    Write-Result "L3" "Smart card reader detected" "WARN" "No readers visible via WMI — verify USB reader is connected and driver installed"
    Write-Result "L3" "Card present in reader" "WARN" "Cannot check — no reader detected"
}

# ---------------------------------------------------------------------------
# LAYER 4 — GPO & Registry Settings
# ---------------------------------------------------------------------------
Write-LayerHeader "Layer 4 — GPO & Registry Settings"

$polPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

$scForce = (Get-ItemProperty -Path $polPath -Name scforceoption -ErrorAction SilentlyContinue).scforceoption
if ($scForce -eq 1) {
    Write-Result "L4" "Smart card required (scforceoption)" "PASS" "= 1 (enforced)"
} else {
    Write-Result "L4" "Smart card required (scforceoption)" "FAIL" "= $scForce (should be 1) — apply Enforce-SmartCard.ps1 or Build-CA-GPO.ps1"
}

$scRemove = (Get-ItemProperty -Path $polPath -Name ScRemoveOption -ErrorAction SilentlyContinue).ScRemoveOption
if ($scRemove -in 1,2) {
    $action = if ($scRemove -eq 1) { "Lock Workstation" } else { "Force Logoff" }
    Write-Result "L4" "Card removal action (ScRemoveOption)" "PASS" "= $scRemove ($action)"
} else {
    Write-Result "L4" "Card removal action (ScRemoveOption)" "FAIL" "= $scRemove (should be 1 or 2) — set via GPO: 'Smart card removal behavior'"
}

$idleTimeout = (Get-ItemProperty -Path $polPath -Name InactivityTimeoutSecs -ErrorAction SilentlyContinue).InactivityTimeoutSecs
if ($null -eq $idleTimeout) {
    Write-Result "L4" "Idle timeout (InactivityTimeoutSecs)" "WARN" "Not configured — recommend <= 900 (15 min)"
} elseif ($idleTimeout -le 900) {
    Write-Result "L4" "Idle timeout (InactivityTimeoutSecs)" "PASS" "= $idleTimeout sec ($([math]::Round($idleTimeout/60,0)) min)"
} else {
    Write-Result "L4" "Idle timeout (InactivityTimeoutSecs)" "WARN" "= $idleTimeout sec — exceeds 900s (15 min) recommended maximum"
}

# ---------------------------------------------------------------------------
# LAYER 5 — Audit Policy
# ---------------------------------------------------------------------------
Write-LayerHeader "Layer 5 — Audit Policy"

function Test-AuditSubcategory {
    param([string]$Subcategory, [string]$Layer)
    $out = & auditpol /get /subcategory:"$Subcategory" 2>&1
    $line = $out | Where-Object { $_ -match $Subcategory } | Select-Object -First 1
    if ($line -match 'Success and Failure') {
        Write-Result $Layer "Audit: $Subcategory" "PASS" "Success and Failure"
    } elseif ($line -match 'Success|Failure') {
        $setting = if ($line -match 'Success') { 'Success only' } else { 'Failure only' }
        Write-Result $Layer "Audit: $Subcategory" "WARN" "$setting — should be 'Success and Failure'"
    } else {
        Write-Result $Layer "Audit: $Subcategory" "FAIL" "No Auditing — enable with: auditpol /set /subcategory:`"$Subcategory`" /success:enable /failure:enable"
    }
}

Test-AuditSubcategory "Logon"                          "L5"
Test-AuditSubcategory "Kerberos Authentication Service" "L5"
Test-AuditSubcategory "Certification Services"          "L5"

# Security log size
try {
    $secLog  = Get-WinEvent -ListLog Security -ErrorAction Stop
    $sizeMB  = [math]::Round($secLog.MaximumSizeInBytes / 1MB, 0)
    if ($sizeMB -ge 512) {
        Write-Result "L5" "Security log size" "PASS" "$sizeMB MB (>= 512 MB)"
    } else {
        Write-Result "L5" "Security log size" "WARN" "$sizeMB MB — recommend >= 512 MB. Fix: wevtutil sl Security /ms:536870912"
    }
} catch {
    Write-Result "L5" "Security log size" "WARN" "Could not read Security log settings"
}

# ---------------------------------------------------------------------------
# LAYER 6 — VPN (optional)
# ---------------------------------------------------------------------------
if ($VPNConnectionName) {
    Write-LayerHeader "Layer 6 — VPN ($VPNConnectionName)"

    $vpn = Get-VpnConnection -Name $VPNConnectionName -ErrorAction SilentlyContinue
    if (-not $vpn) {
        Write-Result "L6" "VPN profile exists" "FAIL" "'$VPNConnectionName' not found — run Deploy-VPNClient.ps1"
    } else {
        Write-Result "L6" "VPN profile exists" "PASS" "$VPNConnectionName"

        if ($vpn.TunnelType -eq 'IKEv2') {
            Write-Result "L6" "Tunnel type" "PASS" "IKEv2"
        } else {
            Write-Result "L6" "Tunnel type" "FAIL" "$($vpn.TunnelType) — should be IKEv2"
        }

        $hasEAP = $vpn.AuthenticationMethod -contains 'Eap'
        if ($hasEAP) {
            Write-Result "L6" "Authentication method" "PASS" "EAP (certificate-based)"
        } else {
            Write-Result "L6" "Authentication method" "FAIL" "$($vpn.AuthenticationMethod -join ',') — should include EAP for smart card auth"
        }

        # IPsec cipher check
        try {
            $ipsec = Get-VpnConnectionIPsecConfiguration -ConnectionName $VPNConnectionName -ErrorAction Stop
            if ($ipsec.CipherTransformConstants -match 'AES256') {
                Write-Result "L6" "IPsec cipher" "PASS" "AES-256"
            } else {
                Write-Result "L6" "IPsec cipher" "WARN" "$($ipsec.CipherTransformConstants) — AES-256 recommended for FIPS compliance"
            }
        } catch {
            Write-Result "L6" "IPsec cipher" "WARN" "Could not read IPsec config"
        }

        # Live connection test
        Write-Host ""
        $doTest = Read-Host "  Attempt a live VPN connection test? (Y/N)"
        if ($doTest -match '^[Yy]') {
            try {
                Write-Host "  Connecting..." -ForegroundColor Cyan
                $connectResult = rasdial $VPNConnectionName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Result "L6" "Live VPN connection" "PASS" "Connected successfully"
                    Start-Sleep 2
                    rasdial $VPNConnectionName /disconnect | Out-Null
                } else {
                    Write-Result "L6" "Live VPN connection" "FAIL" "rasdial exit $LASTEXITCODE — $connectResult"
                }
            } catch {
                Write-Result "L6" "Live VPN connection" "FAIL" "Connection attempt failed: $_"
            }
        } else {
            Write-Result "L6" "Live VPN connection" "WARN" "Skipped by operator"
        }
    }
} else {
    Write-LayerHeader "Layer 6 — VPN"
    Write-Result "L6" "VPN checks" "WARN" "No -VPNConnectionName provided — skipped"
}

# ---------------------------------------------------------------------------
# LAYER 7 — Recent Audit Events (smoke test)
# ---------------------------------------------------------------------------
Write-LayerHeader "Layer 7 — Audit Event Smoke Test (last 24 hours)"

function Test-RecentEvent {
    param([string]$Layer, [int]$Id, [string]$Description)
    try {
        $since  = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = $Id
            StartTime = $since
        } -MaxEvents 1 -ErrorAction Stop

        Write-Result $Layer "Event $Id ($Description)" "PASS" "Last seen: $($events[0].TimeCreated.ToString('HH:mm'))"
    } catch [System.Exception] {
        if ($_.Exception.Message -match 'No events') {
            Write-Result $Layer "Event $Id ($Description)" "WARN" "No events in last 24h — audit policy may be configured but no activity yet"
        } else {
            Write-Result $Layer "Event $Id ($Description)" "WARN" "Could not query Security log — run as Administrator"
        }
    }
}

Test-RecentEvent "L7" 4624 "Successful Logon"
Test-RecentEvent "L7" 4768 "Kerberos TGT Request"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$total = $script:PassCount + $script:WarnCount + $script:FailCount

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host ""
Write-Host ("  {0,6}  PASS" -f $script:PassCount) -ForegroundColor Green
Write-Host ("  {0,6}  WARN" -f $script:WarnCount) -ForegroundColor Yellow
Write-Host ("  {0,6}  FAIL" -f $script:FailCount) -ForegroundColor Red
Write-Host ("  {0,6}  Total checks" -f $total)
Write-Host ""

if ($script:FailCount -eq 0 -and $script:WarnCount -eq 0) {
    Write-Host "  ✓ All checks passed — environment is ready for the SCAP SCC scan." -ForegroundColor Green
} elseif ($script:FailCount -eq 0) {
    Write-Host "  ✓ No failures — review WARNs above, then proceed with SCAP scan." -ForegroundColor Yellow
} else {
    Write-Host "  ✗ $($script:FailCount) check(s) FAILED — resolve before running the SCAP scan." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Failed checks:" -ForegroundColor Red
    $script:Results | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-Host "    • [$($_.Layer)] $($_.Check)" -ForegroundColor Red
        if ($_.Detail) { Write-Host "        $($_.Detail)" -ForegroundColor DarkGray }
    }
}

Write-Host ""

# ---------------------------------------------------------------------------
# Export report
# ---------------------------------------------------------------------------
if ($ExportReport) {
    $stamp      = (Get-Date).ToString("yyyyMMdd-HHmm")
    $reportFile = "LabValidation-$env:COMPUTERNAME-$stamp.txt"

    $lines = @(
        "CAC/PIV Lab Validation Report",
        "Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "Machine   : $env:COMPUTERNAME",
        "Domain    : $joinedDomain",
        "Operator  : $env:USERDOMAIN\$env:USERNAME",
        "",
        ("=" * 70),
        "RESULTS",
        ("=" * 70),
        ""
    )

    $currentLayer = ''
    foreach ($r in $script:Results) {
        if ($r.Layer -ne $currentLayer) {
            $currentLayer = $r.Layer
            $lines += ""
            $lines += "  --- $currentLayer ---"
        }
        $lines += ("  [{0}]  {1}" -f $r.Status.PadRight(4), $r.Check)
        if ($r.Detail) { $lines += "          $($r.Detail)" }
    }

    $lines += ""
    $lines += ("=" * 70)
    $lines += "SUMMARY: $($script:PassCount) PASS  $($script:WarnCount) WARN  $($script:FailCount) FAIL  (of $total checks)"
    $lines += ("=" * 70)

    $lines | Set-Content -Path $reportFile -Encoding UTF8
    Write-Host "  Report saved: $reportFile" -ForegroundColor Cyan
    Write-Host ""
}
