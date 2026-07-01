# Ansible STIG Hardening of LAB-DC01 — Step-by-Step Guide

This is the exact path I followed with you to STIG-harden **LAB-DC01** (Windows
Server 2025, scored against the DISA Server 2022 benchmark) using Ansible from a
WSL control node. Your score went **44.95% → 86.7%** across the three severity tiers.

Run the Windows steps in an **elevated PowerShell** on the Hyper-V host, and the
Ansible steps in a **WSL root shell** (`wsl -d Ubuntu -u root`). Enter WSL on its
own line and wait for the `#` prompt before pasting commands — pasting a multi-line
block into the launch line gets mangled.

---

## What you're driving

```
WSL (Ubuntu + Ansible)            WinRM/HTTPS 5986         LAB-DC01
on the Hyper-V host    ───────────────────────────────▶   10.10.10.10 (via LabInternal)
                                                           Windows Server 2025 DC
```

- Ansible can't run on Windows, so the control node is WSL2 on the host.
- The role is community **ansible-lockdown/Windows-2022-STIG** (no official DISA
  Ansible exists for Windows).
- You measure results with **SCAP SCC**, not Ansible — this role has no audit mode.

---

## The scripts at the top of this folder

| File | You run it on | What it does |
|------|---------------|--------------|
| `Setup-AnsibleControlNode.ps1` | Host (elevated) | Installs WSL2 + Ubuntu, then bootstraps Ansible + the STIG role inside it |
| `bootstrap-wsl.sh` | Inside WSL (called by the above) | Builds a Python venv, installs `ansible` + `pywinrm`, runs `ansible-galaxy install -r requirements.yml` |
| `Enable-WinRM-ForAnsible.ps1` | **LAB-DC01** (elevated) | Creates the HTTPS WinRM listener (5986), NTLM auth, firewall rule from the lab subnets |
| `inventory.ini` | Control node | Defines the `[dc]` group = LAB-DC01 at 10.10.10.10 |
| `ansible.cfg` | Control node | Project config — roles/collections paths, YAML output, `allow_broken_conditionals` |
| `requirements.yml` | Control node | The ansible-lockdown role + `ansible.windows` / `community.windows` collections |
| `group_vars/dc/main.yml` | Control node | WinRM connection settings, safety toggles, and the per-control disables for Server 2025 |
| `group_vars/dc/vault.yml` | Control node | **Encrypted** domain-admin password (never share/zip this) |
| `audit-stig.yml` | Control node | A `--check` play — note: this role isn't check-mode-safe, so use SCAP to measure instead |
| `remediate-stig.yml` | Control node | The enforcing play; you run it by severity tag |
| `GUIDE.md` / `CHANGELOG.md` | — | This guide and the change history |

---

## Step-by-step

### 1. Build the control node (host, elevated)
```powershell
cd C:\path\to\CAC-program\Lab-Kit\08-Ansible-STIG
powershell -ExecutionPolicy Bypass -File .\Setup-AnsibleControlNode.ps1
```
If WSL wasn't installed, it installs it and asks you to reboot — reboot, then run
the same command again. On first WSL launch you'll be asked to create a Linux user;
pick any name (I used `ansible`). Everything Ansible-related lives under **root**, so
from here on you work as root: `wsl -d Ubuntu -u root`.

### 2. Enable WinRM on the DC (host, elevated)
PowerShell Direct runs the script *inside* the DC — no network needed yet:
```powershell
$cred = Get-Credential                       # LAB\Administrator
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Invoke-Command -Session $s -FilePath "C:\path\to\CAC-program\Lab-Kit\08-Ansible-STIG\Enable-WinRM-ForAnsible.ps1"
Remove-PSSession $s
```

### 3. Fix the host/DC IP conflict (host, elevated)
The host was holding the DC's IP `10.10.10.10` on `vEthernet (External)`, so traffic
to the DC looped back to the host. Free that address — the host still reaches the DC
via the LabInternal segment (where the host is `10.10.10.1`):
```powershell
Remove-NetIPAddress -IPAddress 10.10.10.10 -InterfaceAlias 'vEthernet (External)' -Confirm:$false
Test-NetConnection 10.10.10.10 -Port 5986    # expect TcpTestSucceeded : True
```

### 4. Set the credentials (WSL, as root)
```bash
export ANSIBLE_CONFIG=/mnt/c/path/to/CAC-program/Lab-Kit/08-Ansible-STIG/ansible.cfg
cd /mnt/c/path/to/CAC-program/Lab-Kit/08-Ansible-STIG
printf '\e[?2004l'                            # turn off bracketed paste (prevents mangling)
printf "ansible_password: '<DC admin password>'\n" > group_vars/dc/vault.yml
ansible-vault encrypt group_vars/dc/vault.yml   # choose a vault passphrase
```

### 5. Confirm the connection (WSL)
```bash
ansible dc -m ansible.windows.win_ping --ask-vault-pass
```
Expect `LAB-DC01 | SUCCESS => { "ping": "pong" }`. Any ad-hoc `ansible`/playbook run
needs `--ask-vault-pass` because the password file is encrypted.

### 6. Apply the Server-2025 compatibility fixes
These are already baked into this folder, but here's what they are and why (see the
changelog for the exact commands to re-apply if you ever reinstall the role):
- `ansible.cfg`: use the built-in `default` callback + `result_format=yaml` (the old
  `yaml` callback was removed in ansible-core 2.21), and set `allow_broken_conditionals`.
- The role's OS gate (`roles/Windows-2022-STIG/tasks/main.yml`) edited to accept
  Server **2025** as well as 2022.
- `default()` guards added to the role's `stdout`/`stderr` references so skipped
  state-gather tasks don't crash the run.
- In `group_vars/dc/main.yml`: disabled four controls that don't apply to Server 2025
  (`wn22_00_000090` TPM/wmic, `wn22_00_000340` PNRP, `wn22_00_000420`/`000430` FTP),
  and set `win2022stig_disruption_high: false` / `win2022stig_complexity_high: false`
  so service-disrupting changes are left off.

### 7. Remediate by severity, snapshot + measure each time
Snapshot first (host, elevated), then run the tier (WSL), then re-scan with SCAP.
Always include `prelim_tasks` or the CAT tasks hit undefined variables.

```powershell
# host, before each tier:
.\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1 -Mode Create -Label "08-Before-Ansible" -VMs "Lab-DC01"
```
```bash
# WSL:
ansible-playbook remediate-stig.yml --tags prelim_tasks,CAT1 --ask-vault-pass
ansible dc -m ansible.windows.win_ping --ask-vault-pass    # confirm access survived
# ...run SCAP, snapshot 08-After-CAT1, then:
ansible-playbook remediate-stig.yml --tags prelim_tasks,CAT2 --ask-vault-pass
# ...run SCAP, snapshot 08-After-CAT2, then:
ansible-playbook remediate-stig.yml --tags prelim_tasks,CAT3 --ask-vault-pass
```

---

## Results

| Stage | Controls changed | SCAP (Server 2022 benchmark) |
|-------|------------------|------------------------------|
| Baseline | — | 44.95% |
| CAT I | 8 | 45.41% |
| CAT II | 96 | 84% |
| CAT III | 9 | **86.7%** |

The remaining gap is manual AUDIT controls (human review, not automatable), the
disruptive/complex items left off by design, and a few 2025-vs-2022 mismatches.

---

## Gotchas I hit (so you don't again)

- **Run `ansible` in WSL, not PowerShell.** It's a Linux command.
- **Enter WSL first, then paste.** Pasting the bash block onto the `wsl …` launch line
  feeds it to the first-run user prompt. And run `printf '\e[?2004l'` once to stop the
  `^[[200~` bracketed-paste corruption.
- **Every run needs `--ask-vault-pass`** once the password file is encrypted.
- **`10.10.10.10` is the DC, not the host.** If the host claims it, you talk to yourself.
- **This role isn't check-mode-safe** — `--check` breaks on its state-gather tasks. Use
  SCAP to measure, not Ansible.
- **Re-installing the role reverts my patches.** The changelog has the one-liners to
  re-apply them.
