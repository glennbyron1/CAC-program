# Phase 8 Ansible utilities

**Author:** Glenn Byron

Supporting playbooks that complement the STIG remediation flow in the parent
folder. These are standalone — they don't depend on the ansible-lockdown role
or the `remediate-stig.yml` machinery.

## Contents

| File | Purpose |
|---|---|
| `ad-health-check.yml` | Read-only AD hygiene pass — stale accounts, privileged-group membership audit, smart-card-required GPO presence, `ScForceOption=1` policy guard. |
| `cert-expiry-report.yml` | Read-only PKI inventory — Root CA, Issuing CA, user certs, OCSP, CRL expiry windows. Pairs with `Lab-Kit/03-IssuingCA/Monitor-PKIHealth.ps1`. |
| `windows-stig-hardening_SUPERSEDED.yml` | **Deprecated** — v1.0 hand-rolled scaffold preserved for portfolio reference. Use `../remediate-stig.yml` instead. |

## Running the utility playbooks

Same control-node setup as the parent module (`../GUIDE.md` walks you through
the WSL/Ansible bootstrap). Once `ansible dc -m ansible.windows.win_ping`
returns SUCCESS:

```bash
# AD hygiene check
ansible-playbook utilities/ad-health-check.yml --ask-vault-pass

# Cert expiry inventory
ansible-playbook utilities/cert-expiry-report.yml --ask-vault-pass
```

Both are read-only and safe to run against a production-like DC.
