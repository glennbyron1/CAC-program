# Secure Contribution Guidelines

**Author:** Glenn Byron

This is a security-focused repository. Every contribution must follow the rules
in [`POLICY.md`](./POLICY.md). This file is the practical checklist.

## One-Time Setup (per clone)

Install the pre-commit hook so blocked files are caught before they are ever
committed. The hook is not synced by Git automatically, so each clone installs
it once.

**macOS / Linux / Git Bash on Windows:**
```bash
ln -s ../../security/scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**Windows PowerShell (copy instead of symlink):**
```powershell
Copy-Item security\scripts\pre-commit .git\hooks\pre-commit
```

Also create your local scrub map (gitignored, never committed):
```powershell
Copy-Item .scrub-patterns.example.json .scrub-patterns.local.json
```

## Before Every Commit

1. `git status` and `git diff` — confirm you are not staging anything sensitive.
2. Confirm there are no certificates, keys, exports, VM images, or credentials.
3. Run the sanitizer: `.\Scrub-Repo.ps1 -WhatIf`, then `.\Scrub-Repo.ps1`.
4. Commit. The pre-commit hook runs automatically as a backstop.
5. Push. CI (`secret-scan.yml`) re-checks on the server side.

## Never Do This

- Commit `.pfx`, `.p12`, `.key`, `.pem`, `.csr`, `.cer`, `.crt`, `.der`
- Commit VM images (`.vmdk`, `.vhdx`, `.ova`, `.ovf`)
- Commit anything from a CA's `CertLog/` directory or `*.edb` / `*.jrs`
- Commit system backups or PowerShell history
- Commit real domains, hostnames, public IPs, or employee names

## Safe Contributions

- Sanitized PowerShell scripts
- Documentation, diagrams, and `.INF` templates with placeholder values
- Lab-generated, sanitized compliance reports

## If You Slip

If you commit something sensitive, stop and follow
[`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md). Do not just delete the file in
a new commit — Git history keeps it.
