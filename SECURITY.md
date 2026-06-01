# Security Policy

**Author:** Glenn Byron

---

## Supported versions

This is a lab and portfolio reference project. There are no "versions" in the production sense — the `main` branch is the current state.

## Reporting a vulnerability

If you find a security issue in the scripts or documentation — for example, a script that handles credentials insecurely, generates weak keys, or could cause harm if run against a real system — please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email: **286100841+glennbyron1@users.noreply.github.com** with the subject line `[CAC-Lab Security]`. Include:
- What the issue is and where it occurs (script name, line number if possible)
- What a bad actor could do with it
- A suggested fix if you have one

I'll respond within 5 business days and credit you in the changelog when the fix is published (unless you prefer to stay anonymous).

## Scope

This project is designed for **isolated Hyper-V lab environments only**. Please do not run these scripts against production systems without thoroughly reviewing and testing them first. Issues arising from running lab scripts against production infrastructure are out of scope for this policy.

## What this project does and does not contain

- **Does not contain** real certificates, private keys, production credentials, or organizational-specific configuration
- **Does contain** placeholder hostnames (`lab.local`, `Lab-DC01`) and example parameters — substitute your own values
- The CI workflow includes secret scanning on every push; if a real credential somehow ends up in a PR, it will be flagged before merge

## Responsible disclosure

I appreciate researchers who follow coordinated disclosure. If you give me reasonable time to fix a confirmed issue before publishing, I will acknowledge your contribution publicly.
