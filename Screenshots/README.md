# Screenshots

**Purpose:** Real lab captures used in `Demo-Walkthrough.md` and as portfolio evidence.

---

## Captured So Far

| File | Source | Shows | Used By |
|---|---|---|---|
| `02-pin-entry-cert-subject.png` | Lab-WS01, 2026-06-01 15:05 | PIN prompt with `administrator@lab.local` and "Security device" visible | Demo-Walkthrough Step 2 |
| `02b-incorrect-pin-validation.png` | Lab-WS01, 2026-06-01 15:06 | "An incorrect PIN was presented" dialog - proves PIN validation works | Demo-Walkthrough Step 2 supplement |
| `03-pkinit-validation-table.png` | DC01 Security log, 2026-06-02 08:25 | Event 4768 fields annotated - labtech, Pre-Auth Type 16, LAB-CA, 10.10.20.30 (WO02), thumbprint match, Result 0x0 | Demo-Walkthrough Step 3 |
| `07-scap-before-after-side-by-side.png` | Hyper-V host, 2026-06-03 | DC01 SCC All-Settings reports side by side: Before-MFA 44.95% (98 Pass / 120 Fail) vs After-MFA 42.66% (93 Pass / 125 Fail). Same target, same benchmark, only delta is the smart card enforcement | Demo-Walkthrough Step 7 |
| `08-scap-win11-stig-result.png` | SCC Summary Viewer, 2026-06-02 | WO02 scan: Microsoft_Windows_11_STIG, Score 37, 0 errors, 1 warning, links to All Settings / Non-Compliance / XCCDF / OVAL / OCIL / CKL | Demo-Walkthrough Step 7 supplement |
| `evidence-enrollment-ceremony-success.png` | DC01, 2026-06-02 07:26 | `New-TokenEnrollment.ps1` Issuer phase completing for labtech - "Certificate enrolled successfully onto the token" | Portfolio evidence, AC-5 separation of duties |
| `troubleshoot-pre-kerberos-cert-fail.png` | WO02, 2026-06-02 07:28 | "Signing in with a security device isn't supported for your account" - before-state for the KerberosAuthentication cert fix | `TROUBLESHOOTING.md` reference |

---

## Still Pending

These slots in `Demo-Walkthrough.md` still need real captures:

| Slot | What to capture | Where | Blocker |
|---|---|---|---|
| 1 | **Lock screen** showing smart card prompt only, no password field | WO02 after `Win+L` | Waiting on cards (~1 week) |
| 4 | **Session locked** within 2 seconds of card removal (stopwatch optional) | WO02 | Waiting on cards |
| 5 | **VPN connected** via EAP-TLS, no password prompt | WO02 after Step 7 | Waiting on cards + VPN test |
| 6 | **PKI health dashboard** green from `Monitor-PKIHealth.ps1` | DC01 | None — can do now |

---

## Capture Guidelines

- **PNG, not JPG** - text stays crisp for portfolio review
- **Hide real names** - the lab account is `LAB\labtech`, not your real name
- **Hide hostnames outside lab.local** - if Agency or any production name shows, retake
- **No IPs outside `10.10.10.x` or `10.10.20.x`** - those are the only lab subnets
- **Stopwatch for slot 4** - phone stopwatch held next to monitor sells the "< 2 seconds" claim better than animation

---

## Naming Convention

`NN-short-description.png` where NN matches the Demo-Walkthrough.md step number it belongs to.
Use `evidence-` prefix for items that are portfolio-only (not part of the live demo flow).
Use `troubleshoot-` prefix for reference shots that document a problem/fix.

---

*Related: `..\Demo-Walkthrough.md`, `..\Lab-Kit\06-PhysicalEndpoint\Add-Physical-Laptop.md` (Step 5 screenshot checklist)*
