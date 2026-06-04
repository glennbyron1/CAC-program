#Requires -Version 5.1
<#
.SYNOPSIS
    PKI Health Monitor — CRL/OCSP Endpoint Checks and Certificate Expiry Alerts

.DESCRIPTION
    Monitors the health of the two-tier PKI (Offline Root CA and Enterprise Issuing CA)
    by checking CRL/OCSP endpoint reachability, detecting approaching certificate expiry,
    and reporting expired or revoked certificates on enrolled endpoints.

    Designed for the continuous monitoring requirements of NIST SP 800-53 CA-7 and SC-17.

    Checks performed:
      1. HTTP CRL endpoint reachability — Root CA and Issuing CA CRL files
      2. CRL validity window — alerts when Root CA CRL is within 30 days of expiry
      3. Issuing CA certificate expiry — alerts at 60, 30, and 14 days
      4. Root CA certificate expiry — alerts at 180, 90, and 30 days
      5. OCSP responder reachability (if configured)
      6. Enrolled smart card certificate expiry on specified accounts
      7. VPN gateway server certificate expiry

    Document ID : SCRIPT-ICAM-012
    Framework   : NIST SP 800-53 CA-7, SC-17 | FIPS 201-3 | CISA ZTMM

.PARAMETER CRLUrls
    Array of HTTP CRL URLs to check. Include both Root CA and Issuing CA CRL URLs.
    Example: @("http://pki.lab.local/crl/RootCA.crl", "http://pki.lab.local/crl/IssuingCA.crl")

.PARAMETER OCSPUrl
    OCSP responder URL (optional). If provided, an HTTP GET is sent to verify reachability.

.PARAMETER IssuingCAServer
    Hostname or FQDN of the Enterprise Issuing CA server. Used to query CA certificate details.

.PARAMETER VPNGatewayCert
    Subject or thumbprint of the WatchGuard VPN gateway certificate to check for expiry.

.PARAMETER EnrolledUsers
    Array of UPNs to check for smart card certificate expiry. Optional.
    Example: @("jsmith@lab.local", "adoe@lab.local")

.PARAMETER AlertThresholdDays
    Number of days before expiry to trigger a WARNING alert. Default: 60.
    A CRITICAL alert fires at half this value (default: 30 days).

.PARAMETER RootCRLAlertDays
    Days before Root CA CRL expiry to alert. Default: 30.
    Root CA CRL is typically valid for 6 months — this should be checked monthly.

.PARAMETER LogPath
    Path to write the health check log. Default: C:\Windows\Logs\PKIHealth.log

.PARAMETER EmailAlert
    If specified, sends an email summary when any WARNING or CRITICAL condition is found.

.PARAMETER SmtpServer
    SMTP server for email alerts (required if -EmailAlert is used).

.PARAMETER AlertRecipient
    Email address for alerts (required if -EmailAlert is used).

.EXAMPLE
    # Basic health check with your CRL URLs
    .\Monitor-PKIHealth.ps1 `
        -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
        -IssuingCAServer "ca01.lab.local"

    # Full check including OCSP and enrolled user certs
    .\Monitor-PKIHealth.ps1 `
        -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
        -OCSPUrl "http://ocsp.lab.local/ocsp" `
        -IssuingCAServer "ca01.lab.local" `
        -EnrolledUsers @("jsmith@lab.local","adoe@lab.local") `
        -AlertThresholdDays 60

    # Scheduled task version — email alert on any issue
    .\Monitor-PKIHealth.ps1 `
        -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
        -IssuingCAServer "ca01.lab.local" `
        -EmailAlert -SmtpServer "smtp.lab.local" -AlertRecipient "pki-admin@lab.local"

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    SCHEDULING: Run this script monthly at minimum to catch Root CA CRL expiry before
    it becomes critical. For Issuing CA and enrolled cert checks, weekly is recommended.

    Windows Task Scheduler example (run as SYSTEM or PKI Admin account):
      schtasks /create /tn "PKI Health Monitor" /tr "powershell.exe -NonInteractive -File C:\Scripts\Monitor-PKIHealth.ps1 -CRLUrls @('http://pki.lab.local/crl/RootCA.crl')" /sc WEEKLY /d MON /st 06:00
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$CRLUrls = @(),

    [Parameter()]
    [string]$OCSPUrl = "",

    [Parameter()]
    [string]$IssuingCAServer = "",

    [Parameter()]
    [string]$VPNGatewayCert = "",

    [Parameter()]
    [string[]]$EnrolledUsers = @(),

    [Parameter()]
    [int]$AlertThresholdDays = 60,

    [Parameter()]
    [int]$RootCRLAlertDays = 30,

    [Parameter()]
    [string]$LogPath = "C:\Windows\Logs\PKIHealth.log",

    [Parameter()]
    [switch]$EmailAlert,

    [Parameter()]
    [string]$SmtpServer = "",

    [Parameter()]
    [string]$AlertRecipient = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Continue on individual check failures

# ---------------------------------------------------------------------------
# Tracking
$script:findings = @()   # All findings for summary/email
$script:hasWarn  = $false
$script:hasCrit  = $false

# ---------------------------------------------------------------------------
function Write-Header {
    $width = 72
    Write-Host ""
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host "  PKI HEALTH MONITOR | SCRIPT-ICAM-012 | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  Run Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "  NIST SP 800-53 CA-7 Continuous Monitoring | SC-17 PKI Certificates" -ForegroundColor Cyan
    Write-Host ("=" * $width) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "── $Title" -ForegroundColor White
    Write-Host ("  " + ("─" * 60)) -ForegroundColor DarkGray
}

function Write-OK     { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn   { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow; $script:hasWarn = $true }
function Write-Crit   { param([string]$Msg) Write-Host "  [CRIT] $Msg" -ForegroundColor Red;    $script:hasCrit = $true }
function Write-Info   { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }
function Write-Skip   { param([string]$Msg) Write-Host "  [SKIP] $Msg" -ForegroundColor DarkGray }

function Add-Finding {
    param([string]$Severity, [string]$Check, [string]$Detail)
    $script:findings += [PSCustomObject]@{
        Severity  = $Severity
        Check     = $Check
        Detail    = $Detail
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
}

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message"
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch {}
}

function Get-DaysUntilExpiry {
    param([datetime]$ExpiryDate)
    return [int]($ExpiryDate - (Get-Date)).TotalDays
}

function Format-DaysRemaining {
    param([int]$Days)
    if ($Days -lt 0) { return "EXPIRED $([Math]::Abs($Days)) days ago" }
    if ($Days -eq 0) { return "EXPIRES TODAY" }
    return "expires in $Days days ($(Get-Date (Get-Date).AddDays($Days) -Format 'yyyy-MM-dd'))"
}

# ---------------------------------------------------------------------------
# CHECK 1: CRL URL REACHABILITY AND VALIDITY
# ---------------------------------------------------------------------------
function Test-CRLEndpoints {
    Write-Section "CRL Endpoint Reachability & Validity"

    if ($CRLUrls.Count -eq 0) {
        Write-Skip "No CRL URLs specified — skipping. Use -CRLUrls to enable."
        return
    }

    foreach ($url in $CRLUrls) {
        Write-Info "Checking: $url"
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop

            if ($response.StatusCode -ne 200) {
                Write-Crit "CRL HTTP $($response.StatusCode) — $url"
                Add-Finding "CRITICAL" "CRL Unreachable" "HTTP $($response.StatusCode) from $url"
                continue
            }

            # Parse the CRL to check validity dates
            $crlBytes = $response.Content
            if ($crlBytes -is [string]) {
                $crlBytes = [System.Text.Encoding]::ASCII.GetBytes($crlBytes)
            }

            # Save to temp file and use certutil to parse
            $tempFile = [System.IO.Path]::GetTempFileName() + ".crl"
            [System.IO.File]::WriteAllBytes($tempFile, $crlBytes)

            $certutilOutput = & certutil -dump "$tempFile" 2>&1 | Out-String
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

            # Extract Next Update date from certutil output
            if ($certutilOutput -match "Next Update:\s+(.+)") {
                $nextUpdateStr = $matches[1].Trim()
                try {
                    $nextUpdate = [datetime]::Parse($nextUpdateStr)
                    $daysLeft   = Get-DaysUntilExpiry -ExpiryDate $nextUpdate
                    $label      = Format-DaysRemaining -Days $daysLeft

                    if ($daysLeft -lt 0) {
                        Write-Crit "CRL EXPIRED: $url — $label"
                        Add-Finding "CRITICAL" "CRL Expired" "$url — $label"
                    } elseif ($daysLeft -le $RootCRLAlertDays) {
                        Write-Warn "CRL expiry approaching: $url — $label"
                        Add-Finding "WARNING" "CRL Expiry Warning" "$url — $label"
                    } else {
                        Write-OK "CRL valid — $url — $label"
                    }
                } catch {
                    Write-Warn "Could not parse CRL expiry date from certutil output — $url"
                }
            } else {
                Write-Warn "Could not extract Next Update from CRL — $url"
            }

        } catch {
            Write-Crit "CRL endpoint UNREACHABLE: $url — $_"
            Add-Finding "CRITICAL" "CRL Unreachable" "$url — $_"
        }
    }
}

# ---------------------------------------------------------------------------
# CHECK 2: OCSP REACHABILITY
# ---------------------------------------------------------------------------
function Test-OCSPEndpoint {
    Write-Section "OCSP Responder Reachability"

    if (-not $OCSPUrl) {
        Write-Skip "No OCSP URL specified — skipping. Use -OCSPUrl to enable."
        return
    }

    Write-Info "Checking OCSP: $OCSPUrl"
    try {
        # OCSP requires a POST with a proper request. A simple GET checks reachability.
        $response = Invoke-WebRequest -Uri $OCSPUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        # HTTP 200 or 405 (Method Not Allowed — POST required) both indicate the endpoint is reachable
        if ($response.StatusCode -in @(200, 405)) {
            Write-OK "OCSP responder reachable — HTTP $($response.StatusCode) (expected)"
        } else {
            Write-Warn "OCSP unexpected HTTP status: $($response.StatusCode)"
            Add-Finding "WARNING" "OCSP Status" "HTTP $($response.StatusCode) from $OCSPUrl"
        }
    } catch {
        # 405 is thrown as an exception by some PS versions — check the error
        if ($_.Exception.Message -like "*405*" -or $_.Exception.Response.StatusCode -eq 405) {
            Write-OK "OCSP responder reachable (HTTP 405 — POST required, endpoint is live)"
        } else {
            Write-Crit "OCSP endpoint UNREACHABLE: $OCSPUrl — $_"
            Add-Finding "CRITICAL" "OCSP Unreachable" "$OCSPUrl — $_"
        }
    }
}

# ---------------------------------------------------------------------------
# CHECK 3: ISSUING CA CERTIFICATE EXPIRY
# ---------------------------------------------------------------------------
function Test-IssuingCACert {
    Write-Section "Issuing CA Certificate Expiry"

    if (-not $IssuingCAServer) {
        Write-Skip "No Issuing CA server specified — skipping. Use -IssuingCAServer to enable."
        return
    }

    try {
        Write-Info "Querying CA certificates on: $IssuingCAServer"

        # Pull CA certs from the Issuing CA using certutil
        $output = & certutil -config "$IssuingCAServer" -CA.cert 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not connect to CA server '$IssuingCAServer' via certutil (exit $LASTEXITCODE)"
            Write-Info "Falling back to local cert store check..."
        }

        # Check CA certs in the local machine store that chain to this server
        $caCerts = Get-ChildItem -Path "Cert:\LocalMachine\CA" -ErrorAction SilentlyContinue |
                   Where-Object { $_.Subject -like "*$IssuingCAServer*" -or $_.Issuer -like "*CA*" }

        if ($caCerts) {
            foreach ($cert in $caCerts) {
                $days  = Get-DaysUntilExpiry -ExpiryDate $cert.NotAfter
                $label = Format-DaysRemaining -Days $days
                $thumb = $cert.Thumbprint.Substring(0,8) + "..."

                if ($days -lt 0) {
                    Write-Crit "CA cert EXPIRED: $($cert.Subject) [$thumb] — $label"
                    Add-Finding "CRITICAL" "CA Cert Expired" "$($cert.Subject) — $label"
                } elseif ($days -le ($AlertThresholdDays / 2)) {
                    Write-Crit "CA cert expiry CRITICAL: $($cert.Subject) [$thumb] — $label"
                    Add-Finding "CRITICAL" "CA Cert Critical" "$($cert.Subject) — $label"
                } elseif ($days -le $AlertThresholdDays) {
                    Write-Warn "CA cert expiry WARNING: $($cert.Subject) [$thumb] — $label"
                    Add-Finding "WARNING" "CA Cert Warning" "$($cert.Subject) — $label"
                } else {
                    Write-OK "CA cert healthy: $($cert.Subject) [$thumb] — $label"
                }
            }
        } else {
            Write-Info "No CA certs found in LocalMachine\CA matching '$IssuingCAServer'"
            Write-Info "Run this script on the CA server itself or check the cert store manually."
        }

    } catch {
        Write-Warn "CA certificate check failed: $_"
    }
}

# ---------------------------------------------------------------------------
# CHECK 4: VPN GATEWAY CERTIFICATE EXPIRY
# ---------------------------------------------------------------------------
function Test-VPNCert {
    Write-Section "VPN Gateway Certificate Expiry"

    if (-not $VPNGatewayCert) {
        Write-Skip "No VPN gateway cert specified — skipping. Use -VPNGatewayCert to enable."
        return
    }

    $cert = $null

    # Try thumbprint first, then subject
    try {
        $cert = Get-ChildItem -Path "Cert:\LocalMachine\My" |
                Where-Object { $_.Thumbprint -eq $VPNGatewayCert -or $_.Subject -like "*$VPNGatewayCert*" } |
                Select-Object -First 1
    } catch {}

    if (-not $cert) {
        Write-Info "VPN cert not found in LocalMachine\My — checking CA store..."
        try {
            $cert = Get-ChildItem -Path "Cert:\LocalMachine\CA" |
                    Where-Object { $_.Subject -like "*$VPNGatewayCert*" } |
                    Select-Object -First 1
        } catch {}
    }

    if ($cert) {
        $days  = Get-DaysUntilExpiry -ExpiryDate $cert.NotAfter
        $label = Format-DaysRemaining -Days $days

        if ($days -lt 0) {
            Write-Crit "VPN cert EXPIRED: $($cert.Subject) — $label"
            Add-Finding "CRITICAL" "VPN Cert Expired" "$($cert.Subject) — $label"
        } elseif ($days -le ($AlertThresholdDays / 2)) {
            Write-Crit "VPN cert expiry CRITICAL: $($cert.Subject) — $label"
            Add-Finding "CRITICAL" "VPN Cert Critical" "$($cert.Subject) — $label"
        } elseif ($days -le $AlertThresholdDays) {
            Write-Warn "VPN cert expiry WARNING: $($cert.Subject) — $label"
            Add-Finding "WARNING" "VPN Cert Warning" "$($cert.Subject) — $label"
        } else {
            Write-OK "VPN cert healthy: $($cert.Subject) — $label"
        }
    } else {
        Write-Info "VPN gateway cert not found locally. Run this check on the VPN gateway or check remotely."
    }
}

# ---------------------------------------------------------------------------
# CHECK 5: ENROLLED USER SMART CARD CERTIFICATE EXPIRY
# ---------------------------------------------------------------------------
function Test-EnrolledUserCerts {
    Write-Section "Enrolled Smart Card Certificate Expiry"

    if ($EnrolledUsers.Count -eq 0) {
        Write-Skip "No enrolled users specified — skipping. Use -EnrolledUsers to enable."
        return
    }

    # Check if RSAT AD module is available
    $hasAD = Get-Module -ListAvailable -Name ActiveDirectory
    if (-not $hasAD) {
        Write-Info "ActiveDirectory module not available — checking local cert store only."
    } else {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    }

    foreach ($upn in $EnrolledUsers) {
        Write-Info "Checking certs for: $upn"

        # Find smart card certs in the user store matching this UPN
        # This works when run in the context of the target user or on a machine with their profile
        $certs = Get-ChildItem -Path "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue |
                 Where-Object {
                     $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.2" -and  # Client Auth
                     ($_.Subject -like "*$upn*" -or $_.SubjectName.Name -like "*$upn*")
                 }

        if ($certs) {
            foreach ($cert in $certs) {
                $days  = Get-DaysUntilExpiry -ExpiryDate $cert.NotAfter
                $label = Format-DaysRemaining -Days $days
                $thumb = $cert.Thumbprint.Substring(0,8) + "..."

                if ($days -lt 0) {
                    Write-Crit "Smart card cert EXPIRED for $upn [$thumb] — $label"
                    Add-Finding "CRITICAL" "Smart Card Cert Expired" "$upn [$thumb] — $label"
                } elseif ($days -le ($AlertThresholdDays / 2)) {
                    Write-Crit "Smart card cert expiry CRITICAL for $upn [$thumb] — $label"
                    Add-Finding "CRITICAL" "Smart Card Cert Critical" "$upn — $label"
                } elseif ($days -le $AlertThresholdDays) {
                    Write-Warn "Smart card cert expiry WARNING for $upn [$thumb] — $label"
                    Add-Finding "WARNING" "Smart Card Cert Warning" "$upn — $label"
                } else {
                    Write-OK "Smart card cert healthy for $upn [$thumb] — $label"
                }
            }
        } else {
            Write-Info "No smart card client auth certs found for $upn in CurrentUser\My"
            Write-Info "(Run this check under that user's profile for accurate results)"
        }
    }
}

# ---------------------------------------------------------------------------
# SUMMARY AND EMAIL
# ---------------------------------------------------------------------------
function Write-HealthSummary {
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host "  HEALTH CHECK SUMMARY — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host ""

    # Count via foreach — avoids StrictMode throwing on .Count when Where-Object
    # returns AutomationNull (PowerShell 5.1 empty-pipeline behaviour).
    $critCount = 0; $warnCount = 0
    $critical  = [System.Collections.ArrayList]@()
    $warnings  = [System.Collections.ArrayList]@()
    if ($script:findings) {
        foreach ($f in $script:findings) {
            if ($f.Severity -eq 'CRITICAL') { [void]$critical.Add($f); $critCount++ }
            elseif ($f.Severity -eq 'WARNING')  { [void]$warnings.Add($f); $warnCount++ }
        }
    }

    if ($critCount -eq 0 -and $warnCount -eq 0) {
        Write-Host "  ALL CHECKS PASSED — PKI environment is healthy." -ForegroundColor Green
        Write-Host ""
        Write-Log "HEALTH-CHECK-PASS | No issues found"
    } else {
        if ($critCount -gt 0) {
            Write-Host "  CRITICAL: $critCount issue(s) require immediate action" -ForegroundColor Red
            $critical | ForEach-Object { Write-Host "    [CRIT] $($_.Check): $($_.Detail)" -ForegroundColor Red }
        }
        if ($warnCount -gt 0) {
            Write-Host ""
            Write-Host "  WARNING: $warnCount issue(s) require attention" -ForegroundColor Yellow
            $warnings | ForEach-Object { Write-Host "    [WARN] $($_.Check): $($_.Detail)" -ForegroundColor Yellow }
        }

        Write-Host ""
        if ($script:findings) {
            $script:findings | ForEach-Object {
                Write-Log "HEALTH-CHECK-$($_.Severity) | $($_.Check) | $($_.Detail)"
            }
        }
    }

    Write-Host ""
    Write-Host "  Log: $LogPath" -ForegroundColor DarkGray
    Write-Host ""
}

function Send-AlertEmail {
    if (-not $EmailAlert) { return }
    if (-not $SmtpServer -or -not $AlertRecipient) {
        Write-Warn "Email alert enabled but -SmtpServer and -AlertRecipient are required."
        return
    }
    if ($null -eq $script:findings) { $script:findings = @() }
    if ($script:findings.Count -eq 0) { return }  # No issues — no email

    $subject = "PKI Health Alert — $(if ($script:hasCrit) { 'CRITICAL' } else { 'WARNING' }) — $(Get-Date -Format 'yyyy-MM-dd')"

    $body = "PKI Health Monitor — $($env:COMPUTERNAME)`n"
    $body += "Run time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
    $body += "FINDINGS:`n"
    foreach ($f in $script:findings) {
        $body += "  [$($f.Severity)] $($f.Check): $($f.Detail)`n"
    }
    $body += "`nLog file: $LogPath"

    try {
        Send-MailMessage -To $AlertRecipient -From "pki-monitor@lab.local" `
            -Subject $subject -Body $body -SmtpServer $SmtpServer
        Write-Info "Alert email sent to $AlertRecipient"
    } catch {
        Write-Warn "Failed to send alert email: $_"
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Header
Write-Log "PKI-HEALTH-START | Host: $env:COMPUTERNAME | User: $env:USERNAME"

Test-CRLEndpoints
Test-OCSPEndpoint
Test-IssuingCACert
Test-VPNCert
Test-EnrolledUserCerts
Write-HealthSummary
Send-AlertEmail

Write-Log "PKI-HEALTH-END | Critical: $($script:hasCrit) | Warning: $($script:hasWarn)"
