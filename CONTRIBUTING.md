# Contributing

**Author:** Glenn Byron

Thanks for your interest in contributing. This is a personal portfolio and learning project, but contributions that improve accuracy, fix bugs, or extend the lab in useful ways are welcome.

---

## What kinds of contributions are welcome

- **Bug fixes** — a script that errors on a clean Windows Server 2022 install, a broken parameter, a stale path
- **Accuracy improvements** — a NIST control mapping that's wrong, a STIG reference that's outdated, a README that describes something incorrectly
- **Portability improvements** — anything that makes the lab work better on different hardware or slightly different Windows versions
- **Typos and documentation clarity** — always welcome
- **New scripts that fit the project's scope** — discuss in an issue first before building

## What I'm not looking for right now

- Refactors that change the scripting style significantly (I have a consistent pattern — Verb-Noun, guided/logged, idempotent)
- Dependencies on external tools or modules beyond what's already documented
- Changes to placeholder values (`lab.local`, `Lab-DC01`, etc.) — those are intentional

---

## How to contribute

1. **Open an issue first** for anything beyond a small fix — describe what you found and what you'd change. This avoids wasted effort if something isn't in scope.

2. **Fork the repo and create a branch** with a descriptive name:
   ```
   fix/new-labvms-preflight-error
   docs/clarify-enrollment-ceremony
   ```

3. **Test your change** in an actual Hyper-V lab if it touches a script. A script that passes PSScriptAnalyzer but breaks on a real VM isn't ready.

4. **Run the scrub check** before submitting — make sure no real hostnames, IPs, credentials, or organizational identifiers are in your changes:
   ```powershell
   .\Scrub-Repo.ps1 -WhatIf
   ```

5. **Open a pull request** with a clear description of what changed and why.

---

## Style guide

- PowerShell: follow the existing Verb-Noun convention; use `Write-Host` with color for operator feedback; include a `#region` / `#endregion` structure for longer scripts
- Markdown: keep it plain — no unnecessary emoji, no excessive headers for short content
- Author credit: keep `**Author:** Glenn Byron` in any files you significantly modify (add your name too if you write something substantial)

---

## Attribution

By submitting a contribution, you agree that your changes will be licensed under the same MIT License as the rest of the project. You'll be credited in the changelog.

## Code of conduct

Be direct, be honest, be constructive. This is a technical project — keep discussions focused on the work.
