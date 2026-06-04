#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8.4.1 - Creates a short-lived service identity cert template for workloads (apps, services, scripts) that need to authenticate as themselves rather than as a user.

.DESCRIPTION
    Creates a short-lived service identity cert template for workloads (apps, services, scripts) that need to authenticate as themselves rather than as a user.

    Status: SCAFFOLD - structure in place, product-specific bits marked
    as TODO at top. See README.md for the Phase 8 plan and run order.

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 Zero Trust Extension
    Phase      : 8.4.1 - Workload / NPI (optional)
    Run on     : Lab-DC01
    Depends on : Issuing CA, PSPKI
    NIST       : IA-3, IA-5(2), SA-9
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
Write-Host '  |  Phase 8.4.1 - New WorkloadCertTemplate' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

Write-Step "Scaffold script - not yet a turnkey implementation."
Write-Info  "Sub-phase  : 8.4.1 (Workload / NPI (optional))"
Write-Info  "Run on     : Lab-DC01"
Write-Info  "Depends on : Issuing CA, PSPKI"
Write-Info  "NIST       : IA-3, IA-5(2), SA-9"
Write-Host ""
Write-Warn "Open this script in an editor and complete the TODO at top before running in production."
Write-Warn "See Lab-Kit/07-ZeroTrust/README.md for the full Phase 8 plan."
Write-Host ""
