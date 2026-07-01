#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 8 add-on - Sets up the Ansible control node in WSL on THIS Hyper-V host,
    then provisions Ansible + the ansible-lockdown Windows-2022-STIG content.

.DESCRIPTION
    Ansible cannot run natively on Windows, so this stands up a Linux control node
    via WSL2 on the host and bootstraps it. Two-stage because WSL install needs a
    reboot:

      Stage 1 (WSL absent): runs `wsl --install --no-launch` (WSL2 + Ubuntu),
                            then asks you to REBOOT and re-run this script.
      Stage 2 (WSL present): runs bootstrap-wsl.sh inside Ubuntu (as root) to
                            create a venv, install ansible + pywinrm, and pull the
                            STIG role/collections from requirements.yml.

    Run elevated on the Hyper-V host. Safe to re-run.

.PARAMETER Distro
    WSL distro to use/install. Default 'Ubuntu'.

.EXAMPLE
    .\Setup-AnsibleControlNode.ps1

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program / Phase 8 add-on (Ansible STIG)
    Run on     : Hyper-V host (elevated)
    Last Edit  : 2026-06-29
#>

[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |   Phase 8 add-on - Ansible Control Node (WSL setup)  |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# elevation
$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $me.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Fatal 'Run elevated (Administrator) on the Hyper-V host.'
}

# detect WSL
Write-Step 'Phase 1 - WSL presence'
$wslOk = $false
try {
    $status = & wsl.exe --status 2>&1
    if ($LASTEXITCODE -eq 0 -and $status -notmatch 'not installed') { $wslOk = $true }
} catch { $wslOk = $false }

if (-not $wslOk) {
    Write-Warn 'WSL is not installed. Installing WSL2 + Ubuntu now...'
    & wsl.exe --install --no-launch -d $Distro
    Write-Host ''
    Write-Warn 'A REBOOT is required to finish the WSL install.'
    Write-Info  'After rebooting, re-run this script to finish provisioning Ansible.'
    Write-Host ''
    Write-Host '  Next: Restart-Computer  (then re-run Setup-AnsibleControlNode.ps1)' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}
Write-OK 'WSL is available'

# ensure the distro exists
$distros = (& wsl.exe -l -q) -replace "`0","" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $Distro) {
    Write-Warn "$Distro not registered - installing it..."
    & wsl.exe --install --no-launch -d $Distro
    Write-Warn 'If this is the first distro install, reboot and re-run.'
}
Write-OK "Distro: $Distro"
Write-Host ''

# compute the WSL path to this project + bootstrap
$projWin = $PSScriptRoot
$drive   = $projWin.Substring(0,1).ToLower()
$projWsl = "/mnt/$drive" + ($projWin.Substring(2) -replace '\\','/')
Write-Step 'Phase 2 - Bootstrap Ansible inside WSL (as root)'
Write-Info "Project (Windows): $projWin"
Write-Info "Project (WSL)    : $projWsl"
Write-Host ''

# strip CR then run bootstrap, passing the project path explicitly
$cmd = "tr -d '\r' < '$projWsl/bootstrap-wsl.sh' > /tmp/bootstrap-wsl.sh && bash /tmp/bootstrap-wsl.sh '$projWsl'"
& wsl.exe -d $Distro -u root -- bash -lc $cmd
if ($LASTEXITCODE -ne 0) { Write-Fatal "Bootstrap failed (exit $LASTEXITCODE). See output above." }

Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host '    Control node ready. Open Ubuntu and continue in WSL:' -ForegroundColor White
Write-Host "      wsl -d $Distro" -ForegroundColor Yellow
Write-Host "      export ANSIBLE_CONFIG=$projWsl/ansible.cfg" -ForegroundColor Yellow
Write-Host "      cd $projWsl" -ForegroundColor Yellow
Write-Host '      ansible dc -m ansible.windows.win_ping --ask-vault-pass' -ForegroundColor Yellow
Write-Host '    (First enable WinRM on LAB-DC01 with Enable-WinRM-ForAnsible.ps1.)' -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
