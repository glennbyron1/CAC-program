# Security Policy

## Scope

This file covers security issues in the contents of this repository — the
PowerShell scripts, configuration templates, and documentation that compose
the CAC-style ICAM blueprint. It does **not** cover deployed systems built
from this blueprint; those are the responsibility of the operating
organization.

## Reporting a Vulnerability

If you discover a security issue in this repository — for example, a script
that mishandles credentials, a documented procedure that leaks sensitive
material, or a sanitization gap in `Scrub-Repo.ps1` that could allow real
organizational identifiers to leak — please report it privately first.

**Preferred channel:** Open a private GitHub security advisory at
https://github.com/glennbyron1/CAC-program/security/advisories/new

If GitHub advisories are not available to you, contact the maintainer via
the GitHub-provided noreply address shown in the repository README.

Please do **not** open a public issue or pull request for security
vulnerabilities — they can be addressed faster, and more responsibly, when
reported privately first.

## What to Include

A useful report typically includes:

- A description of the issue and its potential impact.
- The file, line numbers, or commit hash where the issue lives.
- A minimal reproduction or proof-of-concept if applicable.
- Your assessment of severity.

## Response Expectations

This is a personal portfolio project maintained on a best-effort basis, not
an enterprise product. The maintainer will acknowledge receipt within seven
days and aim to provide an initial response within fourteen days. Fixes for
confirmed issues will be released as repository commits, with a note in the
commit message and (for material issues) a published security advisory.

## Out of Scope

The following are **not** considered vulnerabilities in this repository:

- Issues in third-party software referenced or invoked by the scripts
  (Active Directory, AD CS, Windows Server, etc.) — report those to their
  respective vendors.
- Misconfiguration of a deployed system built from this blueprint — that is
  the operator's responsibility.
- General compliance gaps documented and acknowledged in the README (the
  Federal Compliance Upgrade Path section enumerates these by design).

## Acknowledgments

Researchers who report valid issues will be credited in the commit message
that fixes the issue, in the published advisory, and (with permission) in
the `AUTHORS.md` file.
