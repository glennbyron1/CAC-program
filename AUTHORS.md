# Authors

This repository was created and is maintained by:

**Glenn Byron** — Initial Author and Maintainer
- GitHub: [@glennbyron1](https://github.com/glennbyron1)
- Contact: via the GitHub-provided noreply address (see Maintainer section in README)

## Project Origin

This project began as the architectural design work for a real enterprise
identity and access management upgrade — replacing a cloud-based software MFA product with hardware-backed, certificate-based smart card authentication
across Windows workstations, VPN, and Microsoft 365.

The committed repository is the *sanitized* version of that work, scrubbed of
real organizational identifiers, intended for public portfolio use and to give
others a working blueprint to build a comparable system in their own labs.

## Contributions

Contributions are welcome. Before submitting a pull request:

1. Read `SECURITY.md` for the responsible-disclosure process if you've found
   a vulnerability in the repository itself (not in any deployed system).
2. Read the security expectations in the README's Security Statement &
   Sanitization section before pushing any change.
3. Run `Scrub-Repo.ps1 -WhatIf` and confirm no real identifiers leak into your
   contribution.

Significant contributors will be listed below.

## Attribution

If you fork or adapt this work, attribution under the MIT License is
appreciated but not required. A link back to the upstream repository is
appreciated when practical.
