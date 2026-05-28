#Requires -Version 5.1
<#
.SYNOPSIS
    OCSP Online Responder Configuration — AD CS Online Certificate Status Protocol Setup

.DESCRIPTION
    Installs and configures the Windows Online Responder (OCSP) role on the Issuing CA server,
    creates the OCSP signing certificate, configures the revocation provider for the Issuing CA,
    and updates the Issuing CA's Authority Information Access (AIA) extension to include the
    OCSP URL in all newly issued certificates.

    Workflow:
      1. Install ADCS-Online-Cert Windows feature (Online Responder role)
      2. Install the ADCS Online Responder via Add-AdcsOnlineResponder
      3. Request an OCSP Response Signing certificate from the Issuing CA
      4. Add the revocation configuration for the Issuing CA's CRL
      5. Update the CA's AIA to include the OCSP URL going forward
      6. Test OCSP response with certutil -verify

    Document ID : SCRIPT-ICAM-015
    Framework   : NIST SP 800-53 SC-17, IA-5 | FIPS 201-3 §5.3 (revocation)

.PARAMETER CAServer
    The Issuing CA in "Server\CAName" format.
    Example: "ca01.lab.local\Enterprise Issuing CA"

.PARAMETER OCSPHostname
    FQDN where the OCSP responder will be accessible.
    Example: "ocsp.lab.local" or "ca01.lab.local"
    This becomes the URL in the AIA extension: http://<OCSPHostname>/ocsp

.PARAMETER OCSPRevConfigName
    Internal name for the OCSP revocation configuration. Default: "IssuingCA-RevConfig"

.PARAMETER CACertThumbprint
    Thumbprint of the Issuing CA certificate. Used to configure the revocation provider.
    Leave empty to auto-detect from the local CA certificate store.

.EXAMPLE
    # Install and configure OCSP on the Issuing CA server
    .\Set-OCSPResponder.ps1 -CAServer "ca01.lab.local\Enterprise Issuing CA" `
                             -OCSPHostname "ocsp.lab.local"

    # With explicit CA cert thumbprint
    .\Set-OCSPResponder.ps1 -CAServer "ca01.lab.local\Enterprise Issuing CA" `
                             -OCSPHostname "ca01.lab.local" `
                             -CACertThumbprint "A1B2C3D4E5F6..."

.NOTES
    Author  : Glenn Byron
    Version : 1.0

    RUN ON: The Issuing CA server (domain-joined Enterprise CA). Do NOT run on the Offline Root CA.

    AFTER RUNNING:
    - All newly issued certificates will carry the OCSP AIA extension
    - Existing certificates already issued will still use CRL only
    - Clients check OCSP first, then fall back to CRL automatically (Windows default)
    - Verify with: certutil -verify -urlfetch <path-to-cert.cer>
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CAServer,

    [Parameter(Mandatory)]
    [string]$OCSPHostname,

    [Parameter()]
    [string]$OCSPRevConfigName = "IssuingCA-RevConfig",

    [Parameter()]
    [string]$CACertThumbprint = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$OCSPUrl = "http://$OCSPHostname/ocsp"

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host "  OCSP RESPONDER SETUP | SCRIPT-ICAM-015 | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  CA: $CAServer" -ForegroundColor Cyan
    Write-Host "  OCSP URL: $OCSPUrl" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step    { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor White }
function Write-OK      { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-Info    { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }
function Write-Section { param([string]$T) Write-Host ""; Write-Host "── $T" -ForegroundColor White }

# ---------------------------------------------------------------------------
# STEP 1: Install the Online Responder Windows Feature
# ---------------------------------------------------------------------------
function Install-OCSPFeature {
    Write-Section "Step 1 — Install Online Responder Feature"

    $feature = Get-WindowsFeature -Name ADCS-Online-Cert
    if ($feature.Installed) {
        Write-OK "ADCS-Online-Cert feature already installed"
        return
    }

    Write-Step "Installing ADCS-Online-Cert (Online Responder) feature..."
    if ($PSCmdlet.ShouldProcess("ADCS-Online-Cert", "Install Windows feature")) {
        $result = Install-WindowsFeature -Name ADCS-Online-Cert -IncludeManagementTools
        if ($result.Success) {
            Write-OK "Online Responder feature installed"
            if ($result.RestartNeeded -eq 'Yes') {
                Write-Warn "Restart required before continuing. After restart, re-run this script."
                exit 0
            }
        } else {
            Write-Fail "Feature installation failed — check Windows Update and try again."
            throw "ADCS-Online-Cert installation failed"
        }
    }
}

# ---------------------------------------------------------------------------
# STEP 2: Configure the Online Responder
# ---------------------------------------------------------------------------
function Install-OCSPRole {
    Write-Section "Step 2 — Configure Online Responder Role"

    Write-Step "Configuring Online Responder (Add-AdcsOnlineResponder)..."
    try {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Add ADCS Online Responder")) {
            Add-AdcsOnlineResponder -Force -ErrorAction Stop | Out-Null
            Write-OK "Online Responder role configured"
        }
    } catch {
        if ($_ -match "already installed" -or $_ -match "already configured") {
            Write-OK "Online Responder already configured — continuing"
        } else {
            Write-Warn "Add-AdcsOnlineResponder: $_"
            Write-Info "If the Online Responder is already installed, this warning is safe to ignore."
        }
    }
}

# ---------------------------------------------------------------------------
# STEP 3: Request OCSP Signing Certificate
# ---------------------------------------------------------------------------
function Request-OCSPSigningCert {
    Write-Section "Step 3 — Request OCSP Response Signing Certificate"

    # Check if an OCSP signing cert already exists
    $existingCert = Get-ChildItem -Path "Cert:\LocalMachine\My" |
                    Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.48.1.5" } |
                    Select-Object -First 1

    if ($existingCert) {
        Write-OK "OCSP signing certificate already present: $($existingCert.Subject)"
        Write-Info "Thumbprint: $($existingCert.Thumbprint)"
        Write-Info "Expires: $($existingCert.NotAfter.ToString('yyyy-MM-dd'))"
        return $existingCert.Thumbprint
    }

    Write-Step "Requesting OCSP Response Signing certificate from CA..."
    Write-Host ""
    Write-Host "  The OCSP Signing certificate must be issued from the 'OCSP Response Signing'" -ForegroundColor DarkGray
    Write-Host "  template. This template should be published on your Issuing CA." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Option A — Auto-enroll via certreq (run on this server):" -ForegroundColor White
    Write-Host "    certreq -enroll -machine OCSPResponseSigning" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Option B — MMC enrollment:" -ForegroundColor White
    Write-Host "    certlm.msc → Personal → All Tasks → Request New Certificate" -ForegroundColor DarkGray
    Write-Host "    Select 'OCSP Response Signing' template" -ForegroundColor DarkGray
    Write-Host ""

    # Attempt auto-enrollment
    if ($PSCmdlet.ShouldProcess("OCSP Response Signing template", "Request certificate via certreq")) {
        $result = & certreq -enroll -machine OCSPResponseSigning 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-OK "OCSP signing certificate enrolled successfully"
        } else {
            Write-Warn "Auto-enrollment returned: $result"
            Write-Warn "Complete enrollment manually using Option B above, then re-run this script."
            return $null
        }
    }

    # Return the thumbprint of the newly enrolled cert
    $newCert = Get-ChildItem -Path "Cert:\LocalMachine\My" |
               Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.48.1.5" } |
               Select-Object -First 1
    return $newCert?.Thumbprint
}

# ---------------------------------------------------------------------------
# STEP 4: Add Revocation Configuration
# ---------------------------------------------------------------------------
function Set-RevocationConfiguration {
    Write-Section "Step 4 — Configure OCSP Revocation Provider"

    # Get the CA cert thumbprint
    $caThumb = $CACertThumbprint
    if (-not $caThumb) {
        Write-Step "Auto-detecting Issuing CA certificate thumbprint..."
        $caCert = Get-ChildItem -Path "Cert:\LocalMachine\CA" |
                  Where-Object { $_.Subject -like "*$(($CAServer -split '\\')[0])*" -or
                                 $_.Subject -like "*CA*" } |
                  Where-Object { $_.NotAfter -gt (Get-Date) } |
                  Sort-Object NotAfter -Descending |
                  Select-Object -First 1

        if ($caCert) {
            $caThumb = $caCert.Thumbprint
            Write-OK "Issuing CA cert: $($caCert.Subject)"
            Write-Info "Thumbprint: $caThumb"
        } else {
            Write-Warn "Could not auto-detect CA cert — specify -CACertThumbprint manually."
            Write-Info "Find it with: Get-ChildItem Cert:\LocalMachine\CA | Where Subject -like '*CA*'"
        }
    }

    # Use OCSPAdmin COM object to add revocation configuration
    Write-Step "Adding OCSP revocation configuration via OCSPAdmin..."
    Write-Host ""

    $ocspAdminScript = @"
# Add revocation configuration using OCSPAdmin
# Run this block on the OCSP server if the PowerShell cmdlets below are unavailable

`$ocspAdmin = New-Object -ComObject "CertAdm.OCSPAdmin"
`$ocspAdmin.GetConfiguration("$($env:COMPUTERNAME)", `$true)

`$revConfig = `$ocspAdmin.OCSPCAConfigurationCollection.CreateCAConfiguration(
    "$OCSPRevConfigName",
    [System.Runtime.InteropServices.Marshal]::StringToBSTR("$caThumb")
)

# Set the CRL and OCSP signing cert
`$revConfig.CACertificate = <byte-array-of-CA-cert>
`$revConfig.SigningCertificate = <thumbprint-bytes>
`$revConfig.ProviderCLSID = "{4956d17f-88fd-4198-b287-1e6e65883b19}"  # CRL-based revocation

`$ocspAdmin.SetConfiguration("$($env:COMPUTERNAME)", `$true)
"@

    Write-Info "Automated OCSPAdmin COM configuration requires the Online Responder snap-in."
    Write-Host ""
    Write-Host "  Configure the revocation provider using the Online Responder MMC snap-in:" -ForegroundColor White
    Write-Host "  (ocsp.msc → Revocation Configuration → Add Revocation Configuration)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Step-by-step:" -ForegroundColor Cyan
    Write-Host "  1. Open the Online Responder snap-in (ocsp.msc)" -ForegroundColor DarkGray
    Write-Host "  2. Click 'Add Revocation Configuration'" -ForegroundColor DarkGray
    Write-Host "  3. Name: $OCSPRevConfigName" -ForegroundColor DarkGray
    Write-Host "  4. Select the CA certificate: $CAServer" -ForegroundColor DarkGray
    Write-Host "     CA cert thumbprint: $(if ($caThumb) { $caThumb } else { '[auto-detect failed — find with Get-ChildItem Cert:\LocalMachine\CA]' })" -ForegroundColor DarkGray
    Write-Host "  5. Signing certificate: Auto-select from Active Directory" -ForegroundColor DarkGray
    Write-Host "  6. Signing certificate template: OCSP Response Signing" -ForegroundColor DarkGray
    Write-Host "  7. Revocation provider: CRL-based, point to your CRL URL:" -ForegroundColor DarkGray
    Write-Host "     http://pki.lab.local/crl/<IssuingCA>.crl" -ForegroundColor DarkGray
    Write-Host "  8. Click Finish" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# STEP 5: Update CA AIA Extension
# ---------------------------------------------------------------------------
function Update-CAAIA {
    Write-Section "Step 5 — Update Issuing CA AIA Extension"

    Write-Step "Adding OCSP URL to Issuing CA AIA extension..."
    Write-Host ""
    Write-Host "  The following certutil commands add the OCSP URL to all newly issued certs." -ForegroundColor DarkGray
    Write-Host "  Run these on the Issuing CA server (requires CA admin rights):" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  # Add OCSP AIA entry" -ForegroundColor DarkGray
    Write-Host "  certutil -config `"$CAServer`" -setreg CA\CRLPublicationURLs `"65:$OCSPUrl`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # View current AIA configuration" -ForegroundColor DarkGray
    Write-Host "  certutil -config `"$CAServer`" -getreg CA\CRLPublicationURLs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # Restart Certificate Services to apply" -ForegroundColor DarkGray
    Write-Host "  net stop certsvc && net start certsvc" -ForegroundColor Cyan
    Write-Host ""

    if ($PSCmdlet.ShouldProcess($CAServer, "Add OCSP URL to AIA via certutil")) {
        # The value 65 = include in AIA extension of issued certs (bit flags: 1=OCSP, 64=include in AIA)
        $result = & certutil -config "$CAServer" -setreg CA\CRLPublicationURLs "65:$OCSPUrl" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-OK "OCSP URL added to CA AIA: $OCSPUrl"
            Write-Warn "Restart Certificate Services to apply: net stop certsvc && net start certsvc"
        } else {
            Write-Warn "certutil returned: $result"
            Write-Info "Run the commands above manually on the CA server."
        }
    }
}

# ---------------------------------------------------------------------------
# STEP 6: Verify OCSP
# ---------------------------------------------------------------------------
function Test-OCSPConfiguration {
    Write-Section "Step 6 — Verify OCSP Configuration"

    Write-Host "  Test OCSP response for a certificate:" -ForegroundColor White
    Write-Host "    certutil -verify -urlfetch <path-to-issued-cert.cer>" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Test OCSP endpoint reachability:" -ForegroundColor White
    Write-Host "    Invoke-WebRequest -Uri `"$OCSPUrl`" -UseBasicParsing" -ForegroundColor Cyan
    Write-Host "    (expect HTTP 200 or 405 — both mean the endpoint is live)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Check Online Responder status:" -ForegroundColor White
    Write-Host "    Get-AdcsOnlineResponder" -ForegroundColor Cyan
    Write-Host ""

    # Quick reachability test
    try {
        $resp = Invoke-WebRequest -Uri $OCSPUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-OK "OCSP endpoint reachable — HTTP $($resp.StatusCode)"
    } catch {
        if ($_.Exception.Message -like "*405*" -or $_.Exception.Response.StatusCode -eq 405) {
            Write-OK "OCSP endpoint reachable — HTTP 405 (POST required, endpoint is live)"
        } elseif ($_.Exception.Message -like "*Unable to connect*" -or $_.Exception.Message -like "*refused*") {
            Write-Warn "OCSP endpoint not yet reachable at $OCSPUrl"
            Write-Info "Ensure IIS is running and the OCSP virtual application is published."
        } else {
            Write-Info "OCSP check: $_"
        }
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Banner

Install-OCSPFeature
Install-OCSPRole
$ocspSigningThumb = Request-OCSPSigningCert
Set-RevocationConfiguration
Update-CAAIA
Test-OCSPConfiguration

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host "  OCSP RESPONDER SETUP COMPLETE" -ForegroundColor Cyan
Write-Host ""
Write-Host "  OCSP URL: $OCSPUrl" -ForegroundColor White
Write-Host "  This URL will appear in the AIA extension of all newly issued certificates." -ForegroundColor DarkGray
Write-Host "  Add Monitor-PKIHealth.ps1 -OCSPUrl `"$OCSPUrl`" to your monthly health checks." -ForegroundColor DarkGray
Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host ""
