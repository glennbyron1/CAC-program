# Lab-Kit / 08-Ansible-STIG

**Author:** Glenn Byron
**Purpose:** Raise LAB-DC01's STIG compliance (currently **44.95%**) using Ansible
remediation, **audit-first**, with smart-card logon kept intact.

---

## Why this looks the way it does

- **Ansible can't run on Windows as a control node.** It runs from Linux and
  manages Windows over **WinRM**. So the control node is **WSL2 on the Hyper-V
  host**, and LAB-DC01 is the *target*.
- **There is no official DISA Ansible for Windows.** DISA ships GPOs + PowerShell.
  This module uses the community **`ansible-lockdown/Windows-2022-STIG`** role,
  which maps to the same Server 2022 benchmark your SCAP SCC scans use.
- **A DC with smart-card logon is fragile under blanket STIG enforcement.** The
  runbook is deliberately: snapshot → audit (no changes) → enforce by severity,
  re-validating logon after each phase.

```
  WSL2 (Ubuntu + Ansible)  --WinRM/HTTPS 5986-->  LAB-DC01 (10.10.10.10)
  on the Hyper-V host                              Domain Controller + Issuing CA
```

---

## Files

| File | Runs on | What it does |
|------|---------|--------------|
| `Setup-AnsibleControlNode.ps1` | Hyper-V host (elevated) | Installs WSL2+Ubuntu, then bootstraps Ansible + the STIG role |
| `bootstrap-wsl.sh` | inside WSL (called by the above) | venv + ansible + pywinrm + `ansible-galaxy install -r requirements.yml` |
| `Enable-WinRM-ForAnsible.ps1` | **LAB-DC01** (elevated) | HTTPS WinRM listener (5986), NTLM, firewall from lab subnets |
| `inventory.ini` | control node | Defines the `[dc]` group = LAB-DC01 |
| `ansible.cfg` | control node | Project config (see world-writable note below) |
| `requirements.yml` | control node | The ansible-lockdown role + `ansible.windows` / `community.windows` |
| `group_vars/dc/main.yml` | control node | WinRM connection + role-tuning guidance |
| `group_vars/dc/vault.yml.example` | control node | Template for the encrypted domain-admin password |
| `audit-stig.yml` | control node | **Audit-only** play (run with `--check --diff`) |
| `remediate-stig.yml` | control node | **Enforcing** play (run by CAT tag) |

---

## Runbook

### 0. Snapshot first (non-negotiable)
From the Hyper-V host:
```powershell
.\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1 -Mode Create -Label "08-Before-Ansible"
```

### 1. Build the control node (Hyper-V host, elevated PowerShell)
```powershell
cd C:\path\to\CAC-program\Lab-Kit\08-Ansible-STIG
.\Setup-AnsibleControlNode.ps1
```
- If WSL wasn't installed, it installs WSL2+Ubuntu and asks you to **reboot**, then
  **re-run** the same command to finish provisioning Ansible.

### 2. Prepare the target (LAB-DC01, elevated)
Transfer the script in via PowerShell Direct (same pattern as the rest of the kit),
then run it on the DC:
```powershell
# from the Hyper-V host
$cred = Get-Credential   # LAB\Administrator
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Copy-Item .\Enable-WinRM-ForAnsible.ps1 -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
# then inside LAB-DC01 (elevated):
C:\Scripts\Enable-WinRM-ForAnsible.ps1
```
Optional: pass `-Thumbprint <hash>` to bind a CA-issued Server Auth cert instead of
the self-signed default (then you can stop ignoring cert validation).

### 3. Credentials (control node, in WSL)
```bash
wsl -d Ubuntu
export ANSIBLE_CONFIG=/mnt/c/path/to/CAC-program/Lab-Kit/08-Ansible-STIG/ansible.cfg
cd /mnt/c/path/to/CAC-program/Lab-Kit/08-Ansible-STIG
cp group_vars/dc/vault.yml.example group_vars/dc/vault.yml
# edit vault.yml -> real LAB\Administrator password, then encrypt it:
ansible-vault encrypt group_vars/dc/vault.yml
```

### 4. Connectivity test
```bash
ansible dc -m ansible.windows.win_ping --ask-vault-pass
# expect: LAB-DC01 | SUCCESS => { "ping": "pong" }
```

### 5. Audit-only (NO changes)
```bash
ansible-playbook audit-stig.yml --check --diff --ask-vault-pass
```
Every **changed** item is a control the role would remediate = your gap list off
the 44.95% baseline. Read it before enforcing anything. Review `ansible-run.log`.

### 6. Tune, then enforce by severity
First open `roles/Windows-2022-STIG/defaults/main.yml`, copy the per-rule toggles
you care about into `group_vars/dc/main.yml`, and decide which controls to **skip**
(anything touching smart-card / certificate logon, PKINIT, or the WinRM admin
account). Then phase it, re-checking smart-card logon after each:
```bash
ansible-playbook remediate-stig.yml --tags CAT1 --ask-vault-pass
# verify DC health + smart-card logon, then:
ansible-playbook remediate-stig.yml --tags CAT2 --skip-tags V-254XXX --ask-vault-pass
# verify again, then:
ansible-playbook remediate-stig.yml --tags CAT3 --ask-vault-pass
```
After each phase, re-run the SCAP SCC scan (`05-Compliance`) and stage the result to
chart the score climbing from 44.95%.

### 7. Rollback
If logon or DC services break:
```powershell
.\Lab-Kit\01-HyperV-Host\New-LabSnapshot.ps1 -Mode Restore -Label "08-Before-Ansible"
```

---

## Gotchas

- **World-writable config:** `/mnt/c` mounts as 0777, so Ansible ignores a cfg in
  the CWD for safety. Always `export ANSIBLE_CONFIG=<full path>/ansible.cfg`
  (bootstrap adds this to `~/.bashrc`).
- **WSL2 → lab network:** WSL2 egresses through the host, which already reaches
  10.10.10.10, so 5986 should be reachable. If not, confirm the host has an
  interface on the lab subnet and the DC firewall rule allows your source.
- **Self-signed listener:** `group_vars/dc/main.yml` sets
  `ansible_winrm_server_cert_validation: ignore`. Use `-Thumbprint` with a CA cert
  to tighten this.
- **Role variable names are versioned with the benchmark** — read the installed
  role's `defaults/main.yml`; don't guess `winNNstig_*` names.
- **NTLM transport** avoids Kerberos realm setup from WSL. Kerberos is cleaner for
  production; it needs `/etc/krb5.conf` pointed at LAB.LOCAL and `pywinrm[kerberos]`.

---

## Safety notes (DC + admin access)

- Never run `remediate-stig.yml` without a fresh `08-Before-Ansible` checkpoint.
- Enforce by CAT level, not all at once; verify the DC is still reachable
  (`ansible dc -m ansible.windows.win_ping`) and DC services healthy between phases.
- LAB-DC01 does **not** require smart-card logon (only the physical endpoint WO02
  does — the DC issues the smart-card-required GPO but admins still log in with
  password). The risk under blanket STIG enforcement is severing the WinRM/RDP
  admin path, not breaking cert logon. The safety guards
  `win2022stig_disruption_hig