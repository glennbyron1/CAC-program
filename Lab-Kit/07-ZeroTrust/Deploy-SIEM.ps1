#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.6.1 - Stands up the SIEM that will receive the Windows Event Forwarding stream the lab already produces (Set-AuditLogForwarding.ps1 from Phase 6).

.DESCRIPTION
    Stands up the SIEM that will receive the Windows Event Forwarding stream the lab already produces (Set-AuditLogForwarding.ps1 from Phase 6).

    Status: SCAFFOLD - structure in place, product-specific bits marked
    as TODO at top. See README.md for the Phase 8 plan and run order.

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.6.1 - Visibility -> Decisioning
    Run on     : New dedicated SIEM VM
    Depends on : WEF subscription (Phase 6)
    NIST       : AU-2, AU-6, AU-12, SI-4
    Last Edit  : 2026-06-03
#>

# ============================================================
# TODO before this scaffold becomes turnkey
# ============================================================
# See README.md and the relevant Architecture/Roadmap doc.
# Fill in product-specific implementation below.
# ============================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |  Phase 8.6.1 - Deploy SIEM' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Write-Step "Scaffold script - not yet a turnkey implementation."
Write-Info  "Sub-phase  : 8.6.1 (Visibility -> Decisioning)"
Write-Info  "Run on     : New dedicated SIEM VM"
Write-Info  "Depends on : WEF subscription (Phase 6)"
Write-Info  "NIST       : AU-2, AU-6, AU-12, SI-4"
Write-Host ""
Write-Warn "Open this script in an editor and complete the TODO at top before running in production."
Write-Warn "See Lab-Kit/07-ZeroTrust/README.md for the full Phase 8 plan."
Write-Host ""
