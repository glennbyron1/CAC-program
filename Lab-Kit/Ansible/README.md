# Ansible — Windows STIG Hardening Playbook

**Author:** Glenn Byron
**Last Updated:** 2026-05-29

Ansible playbook that applies key DISA STIG hardening controls to Windows Server lab machines. Designed to demonstrate Infrastructure as Code (IaC) and DevSecOps automation — the same principle used in DoD environments to enforce consistent, repeatable security baselines across fleets of machines.

---

## What This Does

Automates a subset of the Windows Server 2022 STIG (DISA STIG ID: WN22-*) that is safe to apply non-interactively. Covers:

- Account lockout policy (STIG: WN22-AC-000030/040/050)
- Password complexity and age requirements (WN22-AC-000060/070/080)
- Audit policy — logon/logoff, account management, privilege use (WN22-AU-*)
- Disabling unnecessary services (Print Spooler, LLMNR, SMBv1)
- Windows Firewall enforcement
- Remote Desktop security settings
- Legal notice / warning banner (WN22-SO-000070)
- User Rights Assignment — restricting logon rights

---

## Prerequisites

**On your control machine (not the Windows target):**

```bash
# Install Ansible
pip install ansible pywinrm

# Install the Windows collection
ansible-galaxy collection install ansible.windows community.windows
```

**On each Windows target machine:**

WinRM must be enabled so Ansible can communicate. Run this in an elevated PowerShell session on the target:

```powershell
# Enable WinRM with HTTPS (production) or HTTP (lab only)
winrm quickconfig -q

# For lab use — allow basic auth over HTTP (NOT for production)
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Or use the Ansible provided script for a full setup:
# https://github.com/ansible/ansible/blob/devel/examples/scripts/ConfigureRemotingForAnsible.ps1
```

---

## Usage

```bash
# 1. Copy the inventory template and fill in your machine IPs
cp inventory.ini.example inventory.ini

# 2. Dry run — see what would change without applying anything
ansible-playbook -i inventory.ini windows-stig-hardening.yml --check --diff

# 3. Apply the hardening
ansible-playbook -i inventory.ini windows-stig-hardening.yml

# 4. Apply to a single host only
ansible-playbook -i inventory.ini windows-stig-hardening.yml --limit dc01

# 5. Run a specific section only (using tags)
ansible-playbook -i inventory.ini windows-stig-hardening.yml --tags audit_policy
```

---

## Available Tags

| Tag | What It Applies |
|-----|----------------|
| `account_policy` | Lockout and password policy |
| `audit_policy` | Windows audit policy settings |
| `services` | Disables unnecessary/risky services |
| `firewall` | Windows Firewall enforcement |
| `rdp` | Remote Desktop security settings |
| `legal_banner` | Warning banner text |
| `user_rights` | User Rights Assignment restrictions |

---

## Lab vs. Production

Some settings in this playbook are appropriate for the lab but would need review before applying to production:

- WinRM HTTP (lab only) — production should use WinRM HTTPS with a valid certificate
- The legal banner text uses placeholder language — replace with your organization's approved AUO notice
- Password age requirements may conflict with smart card-enforced environments (where passwords don't expire)

---

*STIG reference: Windows Server 2022 STIG — available at [public.cyber.mil/stigs](https://public.cyber.mil/stigs/)*
*Ansible Windows docs: [docs.ansible.com/ansible/latest/collections/ansible/windows](https://docs.ansible.com/ansible/latest/collections/ansible/windows/)*
