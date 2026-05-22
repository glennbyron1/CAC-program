# Repository Security Policy

**Author:** Glenn Byron

This policy defines what may and may not be committed to this repository. It
exists because the project deals with PKI, smart cards, and certificate
services — categories where a single careless commit (a private key, a CA
database, a VM image) can cause real harm. It is enforced in layers:

| Layer | Mechanism | Where |
| :--- | :--- | :--- |
| Prevent (local) | `.gitignore` | repo root |
| Prevent (local) | pre-commit hook | `security/scripts/pre-commit` |
| Detect (server) | CI secret scan | `.github/workflows/secret-scan.yml` |
| Govern | this policy + contribution rules | `security/` |
| Sanitize | `Scrub-Repo.ps1` | repo root |

> Vulnerability *reporting* (how to report a flaw in this repo) is covered
> separately in the root [`SECURITY.md`](../SECURITY.md). This file is about
> what is allowed *into* the repo.

## NEVER Commit

- Private keys: `.key`, `.pem` (private), `.pfx`, `.p12`
- Certificate signing requests and issued certs: `.csr`, `.cer`, `.crt`, `.der`
- AD CS certificate database and logs: `CertLog/`, `*.edb`, `*.jrs`
- Virtual machine images: `.vmdk`, `.vhdx`, `.ova`, `.ovf`, `.vmem`, `.vmsd`
- Backups and system images: `.bak`, `.backup`, `.wbk`
- PowerShell history or credential logs: `ConsoleHost_history.txt`
- Real organizational identifiers: production domains, hostnames, public IP
  addresses, employee names, internal network topology
- The local scrub map: `.scrub-patterns.local.json`
- Default or example passwords used in any real environment

All of the above are blocked by `.gitignore`, the pre-commit hook, and CI —
but the policy is the source of truth; the tooling enforces it.

## SAFE to Commit

- PowerShell scripts (sanitized, no secrets, no real identifiers)
- Documentation and architecture diagrams
- GPO settings described as text/templates (not raw production backups)
- `.INF` configuration baselines with placeholder values
- Sanitized, lab-generated compliance reports (see `Compliance-Reports/`)

## Key-Handling Rules

- Private keys live only on smart cards, YubiKeys, or HSMs — never in Git,
  shared drives, or email.
- CA private keys are generated on the CA host (or HSM) and never exported.
- Lab certificates are disposable and must never be reused in production.

## Sanitization Before Every Push

1. Ensure `.scrub-patterns.local.json` exists (copy from the example).
2. Run `.\Scrub-Repo.ps1 -WhatIf` to preview, then `.\Scrub-Repo.ps1`.
3. Review with `git diff`, then commit.

## If Sensitive Data Is Committed

Treat it as a compromise. Follow [`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md)
immediately — removing a secret from the working tree is not enough, because
Git history retains it.
