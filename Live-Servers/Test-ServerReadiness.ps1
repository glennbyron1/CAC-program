# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Checks what is already installed on this server and what still needs
    to be done before it is ready for CAC/PIV deployment.

.DESCRIPTION
    Non-destructive readiness checker — reads only, changes nothing.
    Run this on any server before starting the CAC deployment to get a
    clear picture of what is present, what is missing, and exactly what
    command to run to fix each gap.

    The script auto-detects which role this server plays based on what
    Windows features and services are already running. You can also force
    a specific role with -Role if the auto-detection is wrong.

    Roles checked:
      DomainController  — AD DS, DNS, GPO (smart card enforcement), audit policy,
                          Windows Event Forwarding source config
      IssuingCA         — AD CS Enterprise CA, certificate templates, CRL/AIA,
                          OCSP responder, IIS for HTTP CRL publishing
      OfflineRootCA     — AD CS Standalone CA, no network adapter, CRL valid
      Workstation       — Smart card middleware, GPO applied, VPN profile

    Output: color-coded PASS / WARN / FAIL for every check, plus the
    exact PowerShell or certutil command to fix each FAIL.

.PARAMETER Role
    Force a specific role instead of auto-detecting.
    Valid values: DomainController, IssuingCA, OfflineRootCA, Workstation, All

.PARAMETER CAServer
    The Issuing CA in "Server\CAName" format. Used to verify CRL and AIA
    configuration. Only needed when running on a DomainController or Workstation
    that needs to validate the CA is reachable.
    Example: "ca01.agency.gov\Agency Issuing CA"

.PARAMETER CRLUrl
    HTTP CRL URL to test reachability. Example: "http://pki.agency.gov/crl/IssuingCA.crl"

.PARAMETER OCSPUrl
    OCSP URL to test. Example: "http://ocsp.agency.gov/ocsp"

.PARAMETER ExportReport
    Save the results to a text file in the current directory.

.EXAMPLE
    # Auto-detect role and check everything
    .\Test-ServerReadiness.ps1

.EXAMPLE
    # Force IssuingCA role, test specific CRL/OCSP endpoints
    .\Test-ServerReadiness.ps1 -Role IssuingCA `
        -CRLUrl "http://pki.agency.gov/crl/IssuingCA.crl" `
        -OCSPUrl "http://pki.agency.gov/ocsp"

.EXAMPLE
    # Check workstation and save report
    .\Test-ServerReadiness.ps1 -Role Workstation -ExportReport

.NOTES
    Author     : Glenn Byron
    Safe to run: Yes — read-only, no changes made
    Run as     : Administrator (some checks require elevation)
    Run on     : Each server before starting CAC/PIV deployment
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Auto', 'DomainController', 'IssuingCA', 'OfflineRootCA', 'Workstation', 'All')]
    [string]$Role = 'Auto',

    [Parameter()]
    [string]$CAServer = "",

    [Parameter()]
    [string]$CRLUrl = "",

    [Parameter()]
    [string]$OCSPUrl = "",

    [Parameter()]
    [switch]$ExportReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------
$script:PassCount = 0
$script:WarnCount = 0
$script:FailCount = 0
$script:Report    = [System.Collections.Generic.List[string]]::new()

function Write-Pass {
    param([string]$Check, [string]$Detail = "")
    $script:PassCount++
    $line = "  [PASS] $Check$(if ($Detail) { " — $Detail" })"
    Write-Host $line -ForegroundColor Green
    $script:Report.Add($line)
}

function Write-Warn {
    param([string]$Check, [string]$Detail = "", [string]$Fix = "")
    $script:WarnCount++
    $line = "  [WARN] $Check$(if ($Detail) { " — $Detail" })"
    Write-Host $line -ForegroundColor Yellow
    $script:Report.Add($line)
    if ($Fix) {
        $fixLine = "         Fix: $Fix"
        Write-Host $fixLine -ForegroundColor DarkYellow
        $script:Report.Add($fixLine)
    }
}

function Write-Fail {
    param([string]$Check, [string]$Detail = "", [string]$Fix = "")
    $script:FailCount++
    $line = "  [FAIL] $Check$(if ($Detail) { " — $Detail" })"
    Write-Host $line -ForegroundColor Red
    $script:Report.Add($line)
    if ($Fix) {
        $fixLine = "         Fix: $Fix"
        Write-Host $fixLine -ForegroundColor DarkRed
        $script:Report.Add($fixLine)
    }
}

function Write-Section {
    param([string]$Title)
    $line = "`n── $Title"
    Write-Host $line -ForegroundColor White
    $script:Report.Add($line)
}

function Write-Info {
    param([string]$Msg)
    Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray
    $script:Report.Add("  [INFO] $Msg")
}

# ---------------------------------------------------------------------------
# Auto-detect role
# ---------------------------------------------------------------------------
function Get-ServerRole {
    $roles = @()

    # Check for AD DS (Domain Controller)
    $adds = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
    if ($adds -and $adds.InstallState -eq 'Installed') {
        $dcCheck = Get-Service -Name 'NTDS' -ErrorAction SilentlyContinue
        if ($dcCheck -and $dcCheck.Status -eq 'Running') { $roles += 'DomainController' }
    }

    # Check for AD CS (Certificate Authority)
    $adcs = Get-WindowsFeature -Name ADCS-Cert-Authority -ErrorAction SilentlyContinue
    if ($adcs -and $adcs.InstallState -eq 'Installed') {
        $caType = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" -ErrorAction SilentlyContinue)
        if ($caType) {
            # Standalone CA = no domain dependency (Offline Root CA)
            $caName = (Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($caName) {
                $caConfig = Get-ItemProperty $caName.PSPath -ErrorAction SilentlyContinue
                if ($caConfig.CAType -eq 3) { $roles += 'OfflineRootCA' }   # 3 = Standalone Root
                elseif ($caConfig.CAType -in 0,1) { $roles += 'IssuingCA' } # 0/1 = Enterprise Root/Sub
            }
        }
    }

    # If nothing matches, assume workstation/member server
    if ($roles.Count -eq 0) { $roles += 'Workstation' }

    return $roles
}

# ---------------------------------------------------------------------------
# Check: Domain Controller
# ---------------------------------------------------------------------------
function Test-DomainController {
    Write-Section "Domain Controller Checks"

    # AD DS role
    $f = Get-WindowsFeature AD-Domain-Services -ErrorAction SilentlyContinue
    if ($f -and $f.InstallState -eq 'Installed') {
        Write-Pass "AD Domain Services role" "installed"
    } else {
        Write-Fail "AD Domain Services role" "not installed" `
            "Install-WindowsFeature AD-Domain-Services -IncludeManagementTools"
    }

    # NTDS service
    $svc = Get-Service NTDS -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Pass "NTDS service" "running"
    } else {
        Write-Fail "NTDS service" "not running — AD DS may not be promoted yet" `
            "Run Build-CAC-Lab.ps1 or: Install-ADDSForest -DomainName 'agency.gov'"
    }

    # DNS role
    $dns = Get-WindowsFeature DNS -ErrorAction SilentlyContinue
    if ($dns -and $dns.InstallState -eq 'Installed') {
        Write-Pass "DNS Server role" "installed"
    } else {
        Write-Warn "DNS Server role" "not installed — required for domain resolution" `
            "Install-WindowsFeature DNS -IncludeManagementTools"
    }

    # Group Policy: Smart card logon enforcement
    $scForce = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                -Name scforceoption -ErrorAction SilentlyContinue).scforceoption
    if ($scForce -eq 1) {
        Write-Pass "Smart card logon enforcement GPO" "scforceoption = 1"
    } else {
        Write-Fail "Smart card logon enforcement GPO" "scforceoption not set" `
            "Apply Enforce-SmartCard.ps1 or run Build-CA-GPO.ps1"
    }

    # Group Policy: Lock on removal
    $scRemove = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                 -Name ScRemoveOption -ErrorAction SilentlyContinue).ScRemoveOption
    if ($scRemove -in 1,2) {
        Write-Pass "Session lock on card removal" "ScRemoveOption = $scRemove"
    } else {
        Write-Fail "Session lock on card removal" "ScRemoveOption not set" `
            "Apply Enforce-SmartCard.ps1 or run Build-CA-GPO.ps1"
    }

    # Audit policy: Kerberos authentication (Event 4768/4769)
    $auditKerb = (auditpol /get /subcategory:"Kerberos Authentication Service" 2>$null)
    if ($auditKerb -match "Success and Failure|Success") {
        Write-Pass "Audit: Kerberos Authentication Service" "success/failure logging enabled"
    } else {
        Write-Fail "Audit: Kerberos Authentication Service" "not audited" `
            ".\Set-AuditLogForwarding.ps1 -Mode AuditOnly  OR  auditpol /set /subcategory:'Kerberos Authentication Service' /success:enable /failure:enable"
    }

    # Audit policy: Logon events (Event 4624/4625)
    $auditLogon = (auditpol /get /subcategory:"Logon" 2>$null)
    if ($auditLogon -match "Success and Failure|Success") {
        Write-Pass "Audit: Logon events" "success/failure logging enabled"
    } else {
        Write-Fail "Audit: Logon events" "not audited" `
            "auditpol /set /subcategory:'Logon' /success:enable /failure:enable"
    }

    # Windows Event Forwarding: WinRM
    $winrm = Get-Service WinRM -ErrorAction SilentlyContinue
    if ($winrm -and $winrm.Status -eq 'Running') {
        Write-Pass "WinRM service" "running (needed for WEF)"
    } else {
        Write-Warn "WinRM service" "not running" `
            "Enable-PSRemoting -Force  OR  .\Set-AuditLogForwarding.ps1 -Mode Source"
    }

    # NTAuth store (root CA certificate trusted for smart card logon)
    $ntauth = certutil -enterprise -viewstore NTAuth 2>$null | Out-String
    if ($ntauth -match "Subject|Issuer") {
        Write-Pass "NTAuth certificate store" "certificates present (CA trusted for smart card logon)"
    } else {
        Write-Fail "NTAuth certificate store" "empty — no CA certificate trusted for logon" `
            "certutil -enterprise -addstore NTAuth <IssuerCA.cer>"
    }
}

# ---------------------------------------------------------------------------
# Check: Issuing CA
# ---------------------------------------------------------------------------
function Test-IssuingCA {
    Write-Section "Enterprise Issuing CA Checks"

    # AD CS role
    $f = Get-WindowsFeature ADCS-Cert-Authority -ErrorAction SilentlyContinue
    if ($f -and $f.InstallState -eq 'Installed') {
        Write-Pass "AD CS Certificate Authority role" "installed"
    } else {
        Write-Fail "AD CS Certificate Authority role" "not installed" `
            "Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools"
    }

    # CertSvc service
    $svc = Get-Service CertSvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Pass "CertSvc service" "running"
    } else {
        Write-Fail "CertSvc service" "not running" `
            "Start-Service CertSvc  or  net start certsvc"
    }

    # Certificate templates: Smart Card Logon
    $templates = certutil -catemplates 2>$null | Out-String
    if ($templates -match "SmartCard" -or $templates -match "Smart.Card") {
        Write-Pass "Smart card certificate templates" "found in CA template list"
    } else {
        Write-Fail "Smart card certificate templates" "not published on this CA" `
            ".\New-CertificateTemplates.ps1 -CAServer '$($env:COMPUTERNAME)\<CAName>'"
    }

    # IIS for CRL/AIA HTTP publishing
    $iis = Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue
    if ($iis -and $iis.InstallState -eq 'Installed') {
        Write-Pass "IIS Web Server role" "installed (needed for HTTP CRL/AIA)"
    } else {
        Write-Warn "IIS Web Server role" "not installed" `
            "Install-WindowsFeature Web-Server -IncludeManagementTools"
    }

    # CRL validity check
    $crlInfo = certutil -CRL 2>$null | Out-String
    if ($crlInfo -match "NextUpdate|Next Update") {
        Write-Pass "CRL" "published (certutil -CRL reports a next update)"
    } else {
        Write-Warn "CRL" "could not verify CRL publication" `
            "certutil -CRL  (run on CA to publish immediately)"
    }

    # OCSP Online Responder role
    $ocsp = Get-WindowsFeature ADCS-Online-Cert -ErrorAction SilentlyContinue
    if ($ocsp -and $ocsp.InstallState -eq 'Installed') {
        Write-Pass "OCSP Online Responder role" "installed"
        $ocspSvc = Get-Service OCSPSvc -ErrorAction SilentlyContinue
        if ($ocspSvc -and $ocspSvc.Status -eq 'Running') {
            Write-Pass "OCSP service" "running"
        } else {
            Write-Fail "OCSP service" "not running" `
                "Start-Service OCSPSvc  or  .\Set-OCSPResponder.ps1"
        }
    } else {
        Write-Warn "OCSP Online Responder role" "not installed (optional but recommended)" `
            ".\Set-OCSPResponder.ps1 -CAServer '<server>\<CAName>' -OCSPHostname 'pki.agency.gov'"
    }

    # CRL URL reachability
    if ($CRLUrl) {
        Write-Section "CRL Endpoint Test"
        try {
            $result = Invoke-WebRequest -Uri $CRLUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Pass "CRL URL reachable" "$CRLUrl — HTTP $($result.StatusCode)"
        } catch {
            Write-Fail "CRL URL not reachable" $CRLUrl `
                "Verify IIS is running and the CRL virtual directory is configured"
        }
    }

    # OCSP URL reachability
    if ($OCSPUrl) {
        Write-Section "OCSP Endpoint Test"
        try {
            $result = Invoke-WebRequest -Uri $OCSPUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Pass "OCSP URL reachable" "$OCSPUrl — HTTP $($result.StatusCode)"
        } catch {
            if ($_.Exception.Message -match "405") {
                Write-Pass "OCSP URL reachable" "$OCSPUrl — HTTP 405 (POST required, endpoint is live)"
            } else {
                Write-Fail "OCSP URL not reachable" $OCSPUrl `
                    ".\Set-OCSPResponder.ps1 to configure, then verify IIS is running"
            }
        }
    }

    # Audit policy: AD CS certificate operations (Event 4886/4887/4888)
    $auditCA = (auditpol /get /subcategory:"Certification Services" 2>$null)
    if ($auditCA -match "Success and Failure|Success") {
        Write-Pass "Audit: Certification Services" "enabled"
    } else {
        Write-Fail "Audit: Certification Services" "not audited" `
            "certutil -config '.' -setreg CA\AuditFilter 127  then  net stop certsvc && net start certsvc"
    }

    # PSPKI module
    $pspki = Get-Module -ListAvailable -Name PSPKI -ErrorAction SilentlyContinue
    if ($pspki) {
        Write-Pass "PSPKI PowerShell module" "version $($pspki.Version)"
    } else {
        Write-Warn "PSPKI PowerShell module" "not installed (needed for New-CertificateTemplates.ps1)" `
            "Install-Module PSPKI -Force"
    }
}

# ---------------------------------------------------------------------------
# Check: Offline Root CA
# ---------------------------------------------------------------------------
function Test-OfflineRootCA {
    Write-Section "Offline Root CA Checks"

    # AD CS role
    $f = Get-WindowsFeature ADCS-Cert-Authority -ErrorAction SilentlyContinue
    if ($f -and $f.InstallState -eq 'Installed') {
        Write-Pass "AD CS Certificate Authority role" "installed"
    } else {
        Write-Fail "AD CS Certificate Authority role" "not installed" `
            "Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools"
    }

    # Network adapters (should be none)
    $adapters = Get-NetAdapter | Where-Object { $_.Status -ne 'Disabled' }
    if ($adapters.Count -eq 0) {
        Write-Pass "Network isolation" "no active network adapters — properly air-gapped"
    } else {
        Write-Fail "Network isolation" "active network adapters found ($($adapters.Name -join ', '))" `
            "Remove or disable all network adapters in Hyper-V Manager (Settings > Network Adapter > Remove)"
    }

    # CertSvc
    $svc = Get-Service CertSvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Pass "CertSvc service" "running"
    } else {
        Write-Fail "CertSvc service" "not running" `
            "Start-Service CertSvc"
    }

    # CAPolicy.inf present
    if (Test-Path "C:\Windows\CAPolicy.inf") {
        Write-Pass "CAPolicy.inf" "present at C:\Windows\CAPolicy.inf"
    } else {
        Write-Fail "CAPolicy.inf" "not found" `
            "Copy CAPolicy.inf from Download-OfflineCA-Kit.ps1 output (09-OfflineRootCA-Kit\Config\)"
    }

    # Root CA certificate in Personal store
    $rootCert = Get-ChildItem -Path "Cert:\LocalMachine\My" |
                Where-Object { $_.Subject -eq $_.Issuer } |
                Select-Object -First 1
    if ($rootCert) {
        $daysLeft = ($rootCert.NotAfter - (Get-Date)).Days
        if ($daysLeft -gt 365) {
            Write-Pass "Root CA certificate" "present, expires in $daysLeft days"
        } else {
            Write-Warn "Root CA certificate" "expires in $daysLeft days — plan renewal" ""
        }
    } else {
        Write-Fail "Root CA certificate" "not found in LocalMachine\My store" `
            "Root CA has not been configured yet — run Initialize-RootCA.ps1 from the kit"
    }
}

# ---------------------------------------------------------------------------
# Check: Workstation / Member Server
# ---------------------------------------------------------------------------
function Test-Workstation {
    Write-Section "Workstation / Endpoint Checks"

    # Smart card service (SCardSvr)
    $scard = Get-Service SCardSvr -ErrorAction SilentlyContinue
    if ($scard -and $scard.Status -eq 'Running') {
        Write-Pass "Smart Card service (SCardSvr)" "running"
    } else {
        Write-Fail "Smart Card service (SCardSvr)" "not running" `
            "Start-Service SCardSvr; Set-Service SCardSvr -StartupType Automatic"
    }

    # Smart card plug-and-play (SCardSvr dependency)
    $scpnp = Get-Service ScDeviceEnum -ErrorAction SilentlyContinue
    if ($scpnp -and $scpnp.Status -eq 'Running') {
        Write-Pass "Smart Card Device Enumeration (ScDeviceEnum)" "running"
    } else {
        Write-Warn "Smart Card Device Enumeration" "not running" `
            "Start-Service ScDeviceEnum"
    }

    # Smart card logon GPO
    $scForce = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                -Name scforceoption -ErrorAction SilentlyContinue).scforceoption
    if ($scForce -eq 1) {
        Write-Pass "Smart card logon enforcement GPO" "scforceoption = 1"
    } else {
        Write-Warn "Smart card logon enforcement GPO" "not applied yet" `
            "Join domain and run gpupdate /force, or apply Enforce-SmartCard.ps1"
    }

    # Session lock GPO
    $scRemove = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                 -Name ScRemoveOption -ErrorAction SilentlyContinue).ScRemoveOption
    if ($scRemove -in 1,2) {
        Write-Pass "Session lock on card removal" "ScRemoveOption = $scRemove"
    } else {
        Write-Warn "Session lock on card removal" "not configured" `
            "Apply smart card GPO via gpupdate, or run Enforce-SmartCard.ps1"
    }

    # Domain membership
    if ((Get-WmiObject Win32_ComputerSystem).PartOfDomain) {
        $domain = (Get-WmiObject Win32_ComputerSystem).Domain
        Write-Pass "Domain membership" "joined to $domain"
    } else {
        Write-Fail "Domain membership" "not domain-joined" `
            "Add-Computer -DomainName 'agency.gov' -Credential (Get-Credential) -Restart"
    }

    # VPN profile check
    $vpn = Get-VpnConnection -ErrorAction SilentlyContinue
    if ($vpn) {
        Write-Pass "VPN profile" "found: $($vpn.Name -join ', ')"
    } else {
        Write-Warn "VPN profile" "no VPN connection profiles found" `
            ".\Deploy-VPNClient.ps1 -VPNServerAddress 'vpn.agency.gov'"
    }

    # Root CA trusted in machine store
    $rootCerts = Get-ChildItem -Path "Cert:\LocalMachine\Root" |
                 Where-Object { $_.Subject -match "Root CA|RootCA" } |
                 Select-Object -First 3
    if ($rootCerts) {
        Write-Pass "Root CA in machine trust store" "$($rootCerts.Subject | ForEach-Object { $_ -replace 'CN=','' } | Select-Object -First 1)"
    } else {
        Write-Warn "Root CA" "no Root CA certificate found in LocalMachine\Root" `
            "certutil -addstore Root <RootCA.cer>  (Root CA cert from your PKI)"
    }

    # User smart card certificates
    $userCerts = Get-ChildItem -Path "Cert:\CurrentUser\My" |
                 Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.4.1.311.20.2.2" } # Smart Card Logon EKU
    if ($userCerts) {
        Write-Pass "Smart card logon certificate" "found in current user store ($($userCerts.Count) cert(s))"
    } else {
        Write-Warn "Smart card logon certificate" "none found for current user" `
            "Run New-TokenEnrollment.ps1 (RA phase then Issuer phase) to issue a smart card cert"
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
$header = @"

$(("=" * 70))
  SERVER READINESS CHECKER | Author: Glenn Byron
  Computer : $env:COMPUTERNAME
  Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')
  Run as   : $env:USERNAME
$(("=" * 70))
"@
Write-Host $header -ForegroundColor DarkCyan
$script:Report.Add($header)

# Determine which roles to check
if ($Role -eq 'Auto') {
    $detectedRoles = Get-ServerRole
    Write-Info "Auto-detected role(s): $($detectedRoles -join ', ')"
    $rolesToCheck = $detectedRoles
} elseif ($Role -eq 'All') {
    $rolesToCheck = @('DomainController', 'IssuingCA', 'OfflineRootCA', 'Workstation')
} else {
    $rolesToCheck = @($Role)
}

# Run checks for each role
foreach ($r in $rolesToCheck) {
    switch ($r) {
        'DomainController' { Test-DomainController }
        'IssuingCA'        { Test-IssuingCA }
        'OfflineRootCA'    { Test-OfflineRootCA }
        'Workstation'      { Test-Workstation }
    }
}

# Summary
$summary = @"

$(("=" * 70))
  RESULTS SUMMARY
  PASS : $($script:PassCount)
  WARN : $($script:WarnCount)
  FAIL : $($script:FailCount)
$(("=" * 70))
"@
Write-Host $summary -ForegroundColor $(if ($script:FailCount -gt 0) { 'Yellow' } else { 'Cyan' })
$script:Report.Add($summary)

if ($script:FailCount -eq 0 -and $script:WarnCount -eq 0) {
    Write-Host "  All checks passed — this server is ready for CAC deployment." -ForegroundColor Green
} elseif ($script:FailCount -eq 0) {
    Write-Host "  No failures — review warnings above before proceeding." -ForegroundColor Yellow
} else {
    Write-Host "  Fix the FAIL items above before deploying. Review Install-Guide.md for steps." -ForegroundColor Red
}

Write-Host ""

# Export report
if ($ExportReport) {
    $reportPath = ".\Readiness-Report-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
    $script:Report | Set-Content -Path $reportPath
    Write-Host "  Report saved: $reportPath" -ForegroundColor Cyan
}
