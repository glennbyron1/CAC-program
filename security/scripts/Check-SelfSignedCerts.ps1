#Requires -Version 5.1
<#
.SYNOPSIS
    Audits local certificate stores and remote TLS endpoints for self-signed
    certificates, with thumbprint-based protection for a known-good offline CA.

.DESCRIPTION
    Defensive cert-hygiene tool for the lab PKI. Self-signed certs are normal
    inside a two-tier PKI (the offline Root CA is self-signed by design), so a
    naive "flag all self-signed" report buries the real findings in known-good
    noise. This script accepts the offline CA's certificate as a protected
    baseline: any cert with a matching SHA-1 thumbprint is tagged PROTECTED
    (Offline CA) and excluded from the unprotected count.

    Scope:
      1. Local certificate stores
         - LocalMachine\My, Root, CA, AuthRoot, TrustedPublisher
         - CurrentUser\My, Root, CA
      2. Remote TLS endpoints (optional)
         - Probes the cert presented during the TLS handshake on the
           specified host:port pairs.

    Output:
      - Per-finding console line (colored by status)
      - Summary counts (Self-signed unprotected / Protected / Total)
      - CSV export with full disposition (Subject, Issuer, Thumbprint,
        Expiry, Status, Note)

    Read-only. Makes no changes to any cert store or remote host.

.PARAMETER OfflineCACertPath
    Path to the offline Root CA's public certificate file (.cer / .crt /
    .pfx). Used ONLY to extract the SHA-1 thumbprint — the private key is not
    touched and a .pfx without the private key works fine. Any cert in scope
    whose thumbprint matches is marked PROTECTED and excluded from the
    unprotected count.

.PARAMETER RemoteHosts
    Optional array of hostnames or IPs to probe over TLS. Each entry may
    include an explicit port suffix (`host:port`). Entries without a port use
    the `-Port` default.

.PARAMETER Port
    Default TLS port for entries in `-RemoteHosts` that omit one. Default: 443.

.PARAMETER OutputPath
    Directory where the timestamped CSV is written. Defaults to `$env:TEMP`
    so the repo working tree stays clean; pass a path inside the repo only if
    you want the result archived. The directory is created if it does not
    exist. The CSV filename pattern `cert-scan-*.csv` is gitignored.

.PARAMETER ConnectTimeoutMs
    Per-host TCP connect timeout in milliseconds. Default: 3000.

.EXAMPLE
    .\Check-SelfSignedCerts.ps1 -OfflineCACertPath "C:\certs\OfflineRoot.cer"

    Scans local stores only. Protects the supplied offline CA's thumbprint.

.EXAMPLE
    .\Check-SelfSignedCerts.ps1 `
        -OfflineCACertPath "C:\certs\OfflineRoot.cer" `
        -RemoteHosts "dc01.lab.local","pki.lab.local:443","mgmt.lab.local:8443"

    Scans local stores + probes three remote TLS endpoints.

.OUTPUTS
    [PSCustomObject[]] one finding per scanned cert (also written to CSV).
    Columns: Source, Host, Subject, Issuer, Thumbprint, Expiry, Status, Note.

.NOTES
    Author     : Glenn Byron
    Version    : 1.1.0
    Repo       : CAC-program / security/scripts
    Companion  : Scan-LocalRepo.ps1 (sensitive-pattern scanner, gitignored)
    Self-signed detection uses the Subject == Issuer shortcut, which is
    strictly "self-issued." A rigorous check would verify AuthorityKeyId ==
    SubjectKeyId or attempt a signature-self-verify, but for lab inventory
    the shortcut catches every real case.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$OfflineCACertPath,

    [string[]]$RemoteHosts = @(),

    [int]$Port = 443,

    [string]$OutputPath = $env:TEMP,

    [int]$ConnectTimeoutMs = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Load offline CA cert and extract its thumbprint
# ---------------------------------------------------------------------------
try {
    $offlineCACert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        (Resolve-Path -LiteralPath $OfflineCACertPath).Path
    )
    $protectedThumbprint = $offlineCACert.Thumbprint
    Write-Host "`n[Protected] Offline CA cert loaded." -ForegroundColor Cyan
    Write-Host "  Subject   : $($offlineCACert.Subject)"
    Write-Host "  Thumbprint: $protectedThumbprint"
    Write-Host "  This cert will NOT be flagged or modified.`n"
} catch {
    Write-Error "Failed to load offline CA cert: $_"
    exit 1
}

$findings = [System.Collections.Generic.List[PSCustomObject]]::new()

function New-Finding {
    # Note: parameter is -Hostname (not -Host) — $Host is a PowerShell automatic
    # variable. The output column is still named "Host" for CSV readability.
    param($Source, $Hostname, $Subject, $Issuer, $Thumbprint, $Expiry, $Status, $Note)
    [PSCustomObject]@{
        Source     = $Source
        Host       = $Hostname
        Subject    = $Subject
        Issuer     = $Issuer
        Thumbprint = $Thumbprint
        Expiry     = $Expiry
        Status     = $Status
        Note       = $Note
    }
}

# ---------------------------------------------------------------------------
# 1. Local certificate stores
# ---------------------------------------------------------------------------
Write-Host "=== Scanning local certificate stores ===" -ForegroundColor Yellow

$stores = @(
    @{ Location = 'LocalMachine'; Names = @('My','Root','CA','AuthRoot','TrustedPublisher') },
    @{ Location = 'CurrentUser';  Names = @('My','Root','CA') }
)

foreach ($storeGroup in $stores) {
    foreach ($storeName in $storeGroup.Names) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
                $storeName,
                [System.Security.Cryptography.X509Certificates.StoreLocation]($storeGroup.Location)
            )
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)

            foreach ($cert in $store.Certificates) {
                # Subject == Issuer is the practical "self-signed" heuristic.
                # See .NOTES for the rigorous form; this catches every real case.
                $isSelfSigned = $cert.Subject -eq $cert.Issuer
                if (-not $isSelfSigned) { continue }

                $isProtected = $cert.Thumbprint -eq $protectedThumbprint
                $status = if ($isProtected) { 'PROTECTED (Offline CA)' } else { 'SELF-SIGNED' }
                $note   = if ($isProtected) { 'Matches offline CA — do not override' } else { 'Review: not issued by a trusted CA' }

                $findings.Add((New-Finding `
                    -Source     "$($storeGroup.Location)\$storeName" `
                    -Hostname   'localhost' `
                    -Subject    $cert.Subject `
                    -Issuer     $cert.Issuer `
                    -Thumbprint $cert.Thumbprint `
                    -Expiry     $cert.NotAfter.ToString('yyyy-MM-dd') `
                    -Status     $status `
                    -Note       $note
                ))

                $color = if ($isProtected) { 'Green' } else { 'Red' }
                Write-Host "  [$status] $($cert.Subject) | Store: $($storeGroup.Location)\$storeName | Exp: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor $color
            }

            $store.Close()
        } catch {
            Write-Warning "  Could not open store $($storeGroup.Location)\$storeName : $_"
        }
    }
}

# ---------------------------------------------------------------------------
# 2. Remote TLS certificate probing
# ---------------------------------------------------------------------------
if ($RemoteHosts.Count -gt 0) {
    Write-Host "`n=== Scanning remote hosts ===" -ForegroundColor Yellow

    # Captured by the SslStream validation callback. Reset per iteration so a
    # cert from the previous host does not leak into the current finding.
    $script:remoteCert = $null

    foreach ($entry in $RemoteHosts) {
        $script:remoteCert = $null
        $hostName = $entry
        $hostPort = $Port

        if ($entry -match '^(.+):(\d+)$') {
            $hostName = $Matches[1]
            $hostPort = [int]$Matches[2]
        }

        Write-Host "  Probing $hostName`:$hostPort ..." -NoNewline

        $tcpClient = $null
        $sslStream = $null
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectResult = $tcpClient.BeginConnect($hostName, $hostPort, $null, $null)
            $completed = $connectResult.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)

            if (-not $completed) {
                # Timeout — close the socket to abort the pending connect
                Write-Host " TIMEOUT" -ForegroundColor DarkGray
                $findings.Add((New-Finding -Source 'Remote' -Hostname "$hostName`:$hostPort" `
                    -Subject '-' -Issuer '-' -Thumbprint '-' -Expiry '-' `
                    -Status 'UNREACHABLE' -Note "Connect timed out after ${ConnectTimeoutMs}ms"))
                continue
            }

            try {
                $tcpClient.EndConnect($connectResult)
            } catch {
                Write-Host " CONNECT FAILED: $($_.Exception.Message)" -ForegroundColor DarkGray
                $findings.Add((New-Finding -Source 'Remote' -Hostname "$hostName`:$hostPort" `
                    -Subject '-' -Issuer '-' -Thumbprint '-' -Expiry '-' `
                    -Status 'UNREACHABLE' -Note $_.Exception.Message))
                continue
            }

            $sslStream = New-Object System.Net.Security.SslStream(
                $tcpClient.GetStream(), $false,
                # Callback fires on the same thread during AuthenticateAsClient.
                # Accept any cert — we are reading the offered cert, not validating it.
                { param($sender, $certificate, $chain, $sslPolicyErrors)
                    $script:remoteCert = $certificate
                    $true
                }
            )

            try {
                $sslStream.AuthenticateAsClient($hostName)
            } catch {
                # Handshake may fail (e.g. proto mismatch, name mismatch). The
                # cert may still have been captured by the callback above.
            }

            if ($null -eq $script:remoteCert) {
                Write-Host " NO CERT RETRIEVED" -ForegroundColor DarkGray
                $findings.Add((New-Finding -Source 'Remote' -Hostname "$hostName`:$hostPort" `
                    -Subject '-' -Issuer '-' -Thumbprint '-' -Expiry '-' `
                    -Status 'NO CERT' -Note 'TLS handshake completed but no certificate captured'))
                continue
            }

            $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($script:remoteCert)
            $isSelfSigned = $cert2.Subject -eq $cert2.Issuer
            $isProtected  = $cert2.Thumbprint -eq $protectedThumbprint

            $status = if ($isProtected)       { 'PROTECTED (Offline CA)' }
                      elseif ($isSelfSigned)  { 'SELF-SIGNED' }
                      else                    { 'CA-ISSUED' }

            $note = if ($isProtected)         { 'Matches offline CA — do not override' }
                    elseif ($isSelfSigned)    { 'Review: self-signed cert on remote host' }
                    else                      { 'Issued by a CA chain' }

            $findings.Add((New-Finding `
                -Source     'Remote' `
                -Hostname   "$hostName`:$hostPort" `
                -Subject    $cert2.Subject `
                -Issuer     $cert2.Issuer `
                -Thumbprint $cert2.Thumbprint `
                -Expiry     $cert2.NotAfter.ToString('yyyy-MM-dd') `
                -Status     $status `
                -Note       $note
            ))

            $color = switch ($status) {
                'PROTECTED (Offline CA)' { 'Green' }
                'SELF-SIGNED'            { 'Red' }
                default                  { 'Gray' }
            }
            Write-Host " [$status] $($cert2.Subject) | Exp: $($cert2.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor $color

        } catch {
            Write-Host " ERROR: $_" -ForegroundColor DarkYellow
            $findings.Add((New-Finding -Source 'Remote' -Hostname "$hostName`:$hostPort" `
                -Subject '-' -Issuer '-' -Thumbprint '-' -Expiry '-' `
                -Status 'ERROR' -Note $_.ToString()))
        } finally {
            if ($null -ne $sslStream) { try { $sslStream.Dispose() } catch { } }
            if ($null -ne $tcpClient) { try { $tcpClient.Close()   } catch { } }
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Summary ===" -ForegroundColor Yellow

$selfSigned = $findings | Where-Object { $_.Status -eq 'SELF-SIGNED' }
$protected  = $findings | Where-Object { $_.Status -eq 'PROTECTED (Offline CA)' }

Write-Host "  Self-signed (unprotected) : $($selfSigned.Count)" -ForegroundColor $(if ($selfSigned.Count -gt 0) {'Red'} else {'Green'})
Write-Host "  Offline CA (protected)    : $($protected.Count)"  -ForegroundColor Cyan
Write-Host "  Total findings            : $($findings.Count)"

# Export CSV — defaults to $env:TEMP so the repo working tree stays clean.
if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
$csvPath = Join-Path $OutputPath "cert-scan-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$findings | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n  Results saved to: $csvPath`n" -ForegroundColor Cyan

# Emit findings to the pipeline as well, for callers that prefer objects to CSV.
$findings
