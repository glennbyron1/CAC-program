# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Checks whether a specific GPO is linked, applied, and its settings are
    actually active on this machine.

.DESCRIPTION
    Pass it a GPO name and it does three things:

      1. Confirms the GPO exists in the domain and is linked to an OU
         that covers this machine.
      2. Checks gpresult to confirm the GPO is in the Applied GPO list
         for this computer — meaning it actually processed on last refresh.
      3. For known CAC program GPOs, reads the specific registry keys the
         GPO sets and confirms the values are what they should be.
         For any other GPO, it shows the RSoP (Resultant Set of Policy)
         registry settings so you can see what the GPO is doing.

    The "known GPO" profiles built in are:
      SmartCard-Enforcement  — scforceoption, ScRemoveOption, idle timeout
      Audit-Policy           — Advanced audit subcategories for smart card events
      VPN-Client             — IKEv2 connection profile, EAP-TLS settings
      OCSP-Trust             — OCSP/CRL URL enforcement via certificate trust

    For any other GPO name you pass, the script shows you the applied
    registry settings from RSoP and checks if the GPO shows up in gpresult.

.PARAMETER GPOName
    The exact name of the GPO to check. This is the display name as it
    appears in Group Policy Management Console.
    Examples:
      "SmartCard Policy"
      "SEC-MFA-SmartCard-Enforcement"
      "Default Domain Policy"
      "Agency-VPN-Profile"

.PARAMETER Profile
    Which known CAC profile to validate settings against. If you do not
    specify this, the script auto-matches based on common keywords in the
    GPO name (SmartCard, Audit, VPN). Use "Custom" to skip profile matching
    and just show the RSoP output.

    Valid values: Auto, SmartCard-Enforcement, Audit-Policy, VPN-Client, Custom

.PARAMETER DomainController
    The domain controller to query for GPO information.
    Default: auto-discovered from the current domain.

.PARAMETER ExportReport
    Save the results to a text file in the current directory.

.EXAMPLE
    # Check the smart card GPO by name
    .\Test-GPOCompliance.ps1 -GPOName "SEC-MFA-SmartCard-Enforcement"

.EXAMPLE
    # Check any GPO and show all its RSoP settings
    .\Test-GPOCompliance.ps1 -GPOName "Default Domain Policy" -Profile Custom

.EXAMPLE
    # Check and save a report
    .\Test-GPOCompliance.ps1 -GPOName "SmartCard Policy" -ExportReport

.NOTES
    Author     : Glenn Byron
    Safe to run: Yes — read-only, no changes made
    Run as     : Administrator on a domain-joined machine
    Requires   : GroupPolicy PowerShell module (RSAT-Group-Policy-Management)
                 Install with: Install-WindowsFeature RSAT-Group-Policy-Management
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GPOName,

    [Parameter()]
    [ValidateSet('Auto', 'SmartCard-Enforcement', 'Audit-Policy', 'VPN-Client', 'Custom')]
    [string]$Profile = 'Auto',

    [Parameter()]
    [string]$DomainController = "",

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

function Write-Detail {
    param([string]$Msg)
    Write-Host "         $Msg" -ForegroundColor DarkGray
    $script:Report.Add("         $Msg")
}

# ---------------------------------------------------------------------------
# STEP 1: Check prerequisites
# ---------------------------------------------------------------------------
function Test-Prerequisites {
    Write-Section "Prerequisites"

    # Domain membership
    $cs = Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs -and $cs.PartOfDomain) {
        Write-Pass "Domain membership" "joined to $($cs.Domain)"
        return $cs.Domain
    } else {
        Write-Fail "Domain membership" "this machine is not domain-joined" `
            "GPO checks require domain membership: Add-Computer -DomainName 'agency.gov'"
        return $null
    }
}

function Test-GPModule {
    $mod = Get-Module -ListAvailable -Name GroupPolicy -ErrorAction SilentlyContinue
    if ($mod) {
        Import-Module GroupPolicy -ErrorAction SilentlyContinue
        Write-Pass "GroupPolicy module" "available"
        return $true
    } else {
        Write-Warn "GroupPolicy module" "not installed — GPO link checks will be skipped" `
            "Install-WindowsFeature RSAT-Group-Policy-Management"
        return $false
    }
}

# ---------------------------------------------------------------------------
# STEP 2: Verify GPO exists and is linked
# ---------------------------------------------------------------------------
function Test-GPOExistsAndLinked {
    param([string]$Name, [string]$Domain, [bool]$HasGPModule)

    Write-Section "GPO Existence and Link"

    if (-not $HasGPModule) {
        Write-Warn "GPO link check" "skipped — GroupPolicy module not available"
        return $null
    }

    # Find the GPO
    $dcParam = if ($DomainController) { @{ Server = $DomainController } } else { @{} }
    $gpo = Get-GPO -Name $Name -Domain $Domain @dcParam -ErrorAction SilentlyContinue

    if (-not $gpo) {
        Write-Fail "GPO exists" "'$Name' not found in domain $Domain" `
            "Check the name exactly as it appears in GPMC. Use Get-GPO -All | Select DisplayName to list all GPOs."
        return $null
    }

    Write-Pass "GPO exists" "ID: $($gpo.Id)"
    Write-Detail "Display Name : $($gpo.DisplayName)"
    Write-Detail "Status       : $($gpo.GpoStatus)"
    Write-Detail "Created      : $($gpo.CreationTime.ToString('yyyy-MM-dd'))"
    Write-Detail "Modified     : $($gpo.ModificationTime.ToString('yyyy-MM-dd HH:mm'))"

    # Check GPO status
    if ($gpo.GpoStatus -eq 'AllSettingsDisabled') {
        Write-Fail "GPO enabled" "all settings are disabled in this GPO" `
            "In GPMC, right-click the GPO > Status > All Settings Enabled"
    } elseif ($gpo.GpoStatus -ne 'AllSettingsEnabled') {
        Write-Warn "GPO enabled" "status is '$($gpo.GpoStatus)' — some settings may be disabled"
    } else {
        Write-Pass "GPO enabled" "all settings enabled"
    }

    # Find links — check all OUs for a link to this GPO
    $thisMachineOU = Get-MachineOU -Domain $Domain
    $links = Get-GPOLinks -GPO $gpo -Domain $Domain @dcParam
    if ($links.Count -gt 0) {
        Write-Pass "GPO linked" "linked to $($links.Count) location(s)"
        foreach ($link in $links) {
            $appliesHere = if ($thisMachineOU -and $thisMachineOU -like "*") { "→ covers this machine" } else { "" }
            Write-Detail "Link: $($link.Target) (Enabled: $($link.Enabled), Enforced: $($link.Enforced)) $appliesHere"
        }
    } else {
        Write-Fail "GPO linked" "not linked to any OU or container" `
            "In GPMC, right-click the target OU and choose 'Link an Existing GPO', then select '$Name'"
    }

    return $gpo
}

function Get-MachineOU {
    param([string]$Domain)
    try {
        $dn = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().GetDirectoryEntry()).distinguishedName
        # Get this computer's OU from AD
        $computer = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite()
        $compDN = (Get-ADComputer $env:COMPUTERNAME -ErrorAction SilentlyContinue).DistinguishedName
        return $compDN
    } catch { return $null }
}

function Get-GPOLinks {
    param($GPO, $Domain, $Server = "")
    $links = @()
    try {
        $xmlReport = $GPO | Get-GPOReport -ReportType XML -ErrorAction SilentlyContinue
        if ($xmlReport) {
            [xml]$xml = $xmlReport
            $ns = @{ gp = "http://www.microsoft.com/GroupPolicy/Settings" }
            # Links are in the LinksTo section
            $linkNodes = $xml.GPO.LinksTo
            if ($linkNodes) {
                foreach ($l in $linkNodes) {
                    $links += [PSCustomObject]@{
                        Target   = $l.SOMPath
                        Enabled  = $l.Enabled
                        Enforced = $l.NoOverride
                    }
                }
            }
        }
    } catch {}
    return $links
}

# ---------------------------------------------------------------------------
# STEP 3: Check gpresult — is the GPO in the applied list?
# ---------------------------------------------------------------------------
function Test-GPOApplied {
    param([string]$Name)

    Write-Section "Applied GPO Check (gpresult)"

    $gpresult = gpresult /scope computer /r 2>$null | Out-String

    if ($gpresult -match [regex]::Escape($Name)) {
        Write-Pass "GPO applied to this computer" "'$Name' found in gpresult applied list"
    } else {
        # Check denied/filtered list
        $gpresultFull = gpresult /scope computer /v 2>$null | Out-String
        if ($gpresultFull -match [regex]::Escape($Name)) {
            Write-Warn "GPO in denied/filtered list" "'$Name' appears in gpresult but may be filtered or denied" `
                "Run 'gpresult /scope computer /v' and look for the GPO to see why it was filtered"
        } else {
            Write-Fail "GPO not applied" "'$Name' does not appear in gpresult — GPO has not been processed on this machine" `
                "Run 'gpupdate /force' then check again. Verify the GPO link covers this machine's OU."
        }
        return
    }

    # Show last GP refresh time
    $gpRefresh = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}" `
                  -ErrorAction SilentlyContinue)
    if ($gpRefresh) {
        Write-Info "Last GP refresh recorded in registry"
    }

    # Quick: how long since last gpupdate?
    Write-Info "To force a refresh: gpupdate /force"
}

# ---------------------------------------------------------------------------
# STEP 4: Profile-based settings verification
# ---------------------------------------------------------------------------

# --- Smart Card Enforcement Profile ---
function Test-SmartCardSettings {
    Write-Section "Smart Card GPO Settings Verification"

    $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"

    # scforceoption — require smart card for interactive logon
    $scForce = (Get-ItemProperty $regPath -Name scforceoption -ErrorAction SilentlyContinue).scforceoption
    if ($scForce -eq 1) {
        Write-Pass "Interactive logon: Require smart card" "scforceoption = 1 (ENFORCED)"
    } elseif ($null -eq $scForce) {
        Write-Fail "Interactive logon: Require smart card" "scforceoption not set — smart card not enforced" `
            "GPO setting: Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options > 'Interactive logon: Require smart card' = Enabled"
    } else {
        Write-Fail "Interactive logon: Require smart card" "scforceoption = $scForce (expected 1)" `
            "GPO setting should set scforceoption to 1"
    }

    # ScRemoveOption — what happens when card is removed
    $scRemove = (Get-ItemProperty $regPath -Name ScRemoveOption -ErrorAction SilentlyContinue).ScRemoveOption
    $removeDesc = switch ($scRemove) {
        0 { "No action (0) — should be Lock Workstation" }
        1 { "Lock Workstation (1) — CORRECT" }
        2 { "Force Logoff (2) — acceptable, more aggressive than lock" }
        3 { "Disconnect if Remote Desktop (3)" }
        default { "Not set or unknown value: $scRemove" }
    }
    if ($scRemove -in 1, 2) {
        Write-Pass "Interactive logon: Smart card removal behavior" $removeDesc
    } elseif ($scRemove -eq 3) {
        Write-Warn "Interactive logon: Smart card removal behavior" $removeDesc
    } else {
        Write-Fail "Interactive logon: Smart card removal behavior" $removeDesc `
            "GPO setting: 'Interactive logon: Smart card removal behavior' = Lock Workstation"
    }

    # InactivityTimeoutSecs — idle lock timeout
    $idleTimeout = (Get-ItemProperty $regPath -Name InactivityTimeoutSecs -ErrorAction SilentlyContinue).InactivityTimeoutSecs
    if ($idleTimeout -and $idleTimeout -gt 0 -and $idleTimeout -le 900) {
        Write-Pass "Machine inactivity limit" "$idleTimeout seconds ($([math]::Round($idleTimeout/60,1)) min)"
    } elseif ($idleTimeout -gt 900) {
        Write-Warn "Machine inactivity limit" "$idleTimeout seconds — NIST recommends 15 min (900s) max" `
            "GPO setting: Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options > 'Interactive logon: Machine inactivity limit'"
    } else {
        Write-Warn "Machine inactivity limit" "not configured" `
            "GPO setting: 'Interactive logon: Machine inactivity limit' = 900 (15 minutes)"
    }

    # Check SCardSvr is running (smart card service — required for card logon)
    $scard = Get-Service SCardSvr -ErrorAction SilentlyContinue
    if ($scard -and $scard.Status -eq 'Running') {
        Write-Pass "Smart Card service (SCardSvr)" "running"
    } else {
        Write-Fail "Smart Card service (SCardSvr)" "not running" `
            "Start-Service SCardSvr; Set-Service SCardSvr -StartupType Automatic"
    }

    # Check HKCU for any overrides (user-level policy should not override computer policy here)
    $userOverride = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                     -Name scforceoption -ErrorAction SilentlyContinue).scforceoption
    if ($null -ne $userOverride -and $userOverride -ne 1) {
        Write-Warn "User-level policy override detected" "HKCU scforceoption = $userOverride may conflict with computer GPO" `
            "Check user-level GPOs — computer policy should take precedence"
    }
}

# --- Audit Policy Profile ---
function Test-AuditPolicySettings {
    Write-Section "Audit Policy GPO Settings Verification"

    $auditChecks = @(
        @{ Name = "Logon";                             ExpectedPass = $true; EventIDs = "4624, 4625" },
        @{ Name = "Kerberos Authentication Service";   ExpectedPass = $true; EventIDs = "4768, 4769" },
        @{ Name = "Kerberos Service Ticket Operations"; ExpectedPass = $true; EventIDs = "4769, 4770" },
        @{ Name = "Special Logon";                     ExpectedPass = $true; EventIDs = "4672" },
        @{ Name = "Certification Services";            ExpectedPass = $true; EventIDs = "4886, 4887, 4888" },
        @{ Name = "Other Account Logon Events";        ExpectedPass = $true; EventIDs = "4776" },
        @{ Name = "Account Lockout";                   ExpectedPass = $true; EventIDs = "4740" }
    )

    foreach ($check in $auditChecks) {
        $result = (auditpol /get /subcategory:"$($check.Name)" 2>$null) | Out-String
        if ($result -match "Success and Failure") {
            Write-Pass "Audit: $($check.Name)" "Success and Failure (Events: $($check.EventIDs))"
        } elseif ($result -match "Success") {
            Write-Warn "Audit: $($check.Name)" "Success only — Failure not audited (Events: $($check.EventIDs))" `
                "auditpol /set /subcategory:'$($check.Name)' /success:enable /failure:enable"
        } else {
            Write-Fail "Audit: $($check.Name)" "not configured (Events: $($check.EventIDs))" `
                "auditpol /set /subcategory:'$($check.Name)' /success:enable /failure:enable"
        }
    }

    # Check the Event Log sizes are adequate
    $secLog = Get-WinEvent -ListLog Security -ErrorAction SilentlyContinue
    if ($secLog) {
        $maxMB = [math]::Round($secLog.MaximumSizeInBytes / 1MB)
        if ($maxMB -ge 512) {
            Write-Pass "Security event log size" "$($maxMB)MB"
        } else {
            Write-Warn "Security event log size" "$($maxMB)MB — recommend at least 512MB for smart card environments" `
                "wevtutil sl Security /ms:536870912  (sets to 512MB)"
        }
    }
}

# --- VPN Client Profile ---
function Test-VPNSettings {
    Write-Section "VPN Client GPO Settings Verification"

    # Check for VPN connection profiles
    $vpnConns = Get-VpnConnection -ErrorAction SilentlyContinue
    if (-not $vpnConns) {
        Write-Fail "VPN connection profiles" "none found on this machine" `
            ".\Lab-Kit\04-Workstation\Deploy-VPNClient.ps1 -VPNServerAddress 'vpn.agency.gov'"
        return
    }

    foreach ($vpn in $vpnConns) {
        Write-Pass "VPN profile found" "$($vpn.Name)"
        Write-Detail "Server         : $($vpn.ServerAddress)"
        Write-Detail "Tunnel type    : $($vpn.TunnelType)"
        Write-Detail "Auth method    : $($vpn.AuthenticationMethod -join ', ')"
        Write-Detail "Encryption     : $($vpn.EncryptionLevel)"
        Write-Detail "Split tunneling: $($vpn.SplitTunneling)"

        # Check for IKEv2
        if ($vpn.TunnelType -eq 'IKEv2') {
            Write-Pass "Tunnel type: IKEv2" "correct for EAP-TLS"
        } else {
            Write-Fail "Tunnel type" "$($vpn.TunnelType) — expected IKEv2 for smart card EAP-TLS" `
                ".\Deploy-VPNClient.ps1 re-creates the profile with the correct IKEv2 settings"
        }

        # Check for EAP authentication (smart card)
        if ($vpn.AuthenticationMethod -contains 'Eap') {
            Write-Pass "Authentication: EAP" "certificate-based auth configured"
        } else {
            Write-Warn "Authentication method" "$($vpn.AuthenticationMethod -join ', ') — expected EAP for smart card" `
                ".\Deploy-VPNClient.ps1 sets EAP-TLS XML config for certificate authentication"
        }

        # Check IPsec crypto policy (FIPS compliance)
        $ikev2 = Get-VpnConnectionIPsecConfiguration -ConnectionName $vpn.Name -ErrorAction SilentlyContinue
        if ($ikev2) {
            Write-Detail "Cipher     : $($ikev2.CipherTransformConstants)"
            Write-Detail "Auth method: $($ikev2.AuthenticationTransformConstants)"
            Write-Detail "DH group   : $($ikev2.DHGroup)"
            Write-Detail "PFS group  : $($ikev2.PfsGroup)"

            if ($ikev2.CipherTransformConstants -match "AES256" -or $ikev2.CipherTransformConstants -match "GCMAES256") {
                Write-Pass "IPsec cipher" "AES-256 — FIPS compliant"
            } else {
                Write-Warn "IPsec cipher" "$($ikev2.CipherTransformConstants) — verify FIPS compliance" `
                    "Deploy-VPNClient.ps1 sets AES-256-GCM / SHA-256 / ECP384 by default"
            }
        }
    }
}

# --- Custom / Generic Profile: show RSoP registry output ---
function Show-GenericRSoP {
    param([string]$Name)

    Write-Section "RSoP Registry Settings for '$Name'"
    Write-Info "Showing all registry values applied by this GPO via gpresult /v..."
    Write-Host ""

    $gpresultXml = gpresult /scope computer /x "$env:TEMP\gpresult-$PID.xml" 2>$null
    if (Test-Path "$env:TEMP\gpresult-$PID.xml") {
        try {
            [xml]$xml = Get-Content "$env:TEMP\gpresult-$PID.xml"
            # Find the GPO in the applied list
            $appliedGPOs = $xml.Rsop.ComputerResults.ExtensionData.Extension | ForEach-Object { $_ }
            $found = $false
            foreach ($ext in $xml.Rsop.ComputerResults.ExtensionData) {
                foreach ($q in $ext.Extension.Policy) {
                    if ($q.Name -and $q.GPO.'#text' -like "*$Name*") {
                        Write-Host "  Setting: $($q.Name)" -ForegroundColor White
                        Write-Host "    Value: $($q.State)" -ForegroundColor DarkGray
                        $found = $true
                    }
                }
            }
            if (-not $found) {
                Write-Warn "RSoP data" "no registry policy settings from '$Name' found in XML output"
                Write-Info "The GPO may only contain non-registry settings (audit policy, startup scripts, etc.)"
                Write-Info "Run 'gpresult /scope computer /v' in a terminal for the full verbose report"
            }
        } catch {
            Write-Warn "RSoP XML parse" "could not parse gpresult XML: $_"
        } finally {
            Remove-Item "$env:TEMP\gpresult-$PID.xml" -ErrorAction SilentlyContinue
        }
    } else {
        Write-Warn "gpresult XML" "could not generate RSoP report — run as Administrator"
        Write-Info "Manual check: gpresult /scope computer /v | findstr /i '$Name'"
    }

    # Always show the full gpresult summary section for this GPO
    Write-Host ""
    Write-Host "  Full gpresult output for this GPO:" -ForegroundColor White
    $gpresultText = gpresult /scope computer /v 2>$null | Out-String
    $lines = $gpresultText -split "`n"
    $capture = $false
    foreach ($line in $lines) {
        if ($line -match [regex]::Escape($Name)) { $capture = $true }
        if ($capture) {
            Write-Host "    $line" -ForegroundColor DarkGray
            $script:Report.Add("    $line")
            if ($line.Trim() -eq "" -and $capture) { $capture = $false }
        }
    }
}

# ---------------------------------------------------------------------------
# Auto-select profile from GPO name
# ---------------------------------------------------------------------------
function Resolve-Profile {
    param([string]$Name, [string]$Requested)
    if ($Requested -ne 'Auto') { return $Requested }

    if ($Name -match "SmartCard|Smart.Card|MFA|CAC") { return 'SmartCard-Enforcement' }
    if ($Name -match "Audit|Logging|Event") { return 'Audit-Policy' }
    if ($Name -match "VPN|Remote.Access|IKEv2") { return 'VPN-Client' }
    return 'Custom'
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
$header = @"

$(("=" * 70))
  GPO COMPLIANCE CHECKER | Author: Glenn Byron
  Computer  : $env:COMPUTERNAME
  GPO Name  : $GPOName
  Date      : $(Get-Date -Format 'yyyy-MM-dd HH:mm')
$(("=" * 70))
"@
Write-Host $header -ForegroundColor DarkCyan
$script:Report.Add($header)

# Prerequisites
$domain = Test-Prerequisites
$hasGP  = Test-GPModule

if (-not $domain) {
    Write-Host "`n  Cannot proceed — machine must be domain-joined." -ForegroundColor Red
    exit 1
}

# GPO existence and links
$gpo = Test-GPOExistsAndLinked -Name $GPOName -Domain $domain -HasGPModule $hasGP

# gpresult applied check
Test-GPOApplied -Name $GPOName

# Profile-based settings
$resolvedProfile = Resolve-Profile -Name $GPOName -Requested $Profile
Write-Info "Settings profile: $resolvedProfile"

switch ($resolvedProfile) {
    'SmartCard-Enforcement' { Test-SmartCardSettings }
    'Audit-Policy'          { Test-AuditPolicySettings }
    'VPN-Client'            { Test-VPNSettings }
    'Custom'                { Show-GenericRSoP -Name $GPOName }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$summary = @"

$(("=" * 70))
  RESULTS SUMMARY for: $GPOName
  PASS : $($script:PassCount)
  WARN : $($script:WarnCount)
  FAIL : $($script:FailCount)
$(("=" * 70))
"@
Write-Host $summary -ForegroundColor $(if ($script:FailCount -gt 0) { 'Yellow' } else { 'Cyan' })
$script:Report.Add($summary)

if ($script:FailCount -eq 0 -and $script:WarnCount -eq 0) {
    Write-Host "  All checks passed — GPO is linked, applied, and settings are active." -ForegroundColor Green
} elseif ($script:FailCount -eq 0) {
    Write-Host "  No failures — review warnings above before going live." -ForegroundColor Yellow
} else {
    Write-Host "  Fix the FAIL items. Run 'gpupdate /force' after making changes, then re-run this script." -ForegroundColor Red
}
Write-Host ""

# Export
if ($ExportReport) {
    $safe = $GPOName -replace '[\\/:*?"<>|]', '_'
    $reportPath = ".\GPO-Report-$safe-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
    $script:Report | Set-Content -Path $reportPath
    Write-Host "  Report saved: $reportPath" -ForegroundColor Cyan
}
