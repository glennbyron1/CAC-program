# Screenshots

**Purpose:** Real lab captures used in `Demo-Walkthrough.md` and as portfolio evidence.

---

## Captured So Far

### Demo-Walkthrough headline shots

| File | Source | Shows | Used By |
|---|---|---|---|
| `01-lockscreen-smartcard-only.png` | WO02, 2026-06-16 | Lock screen showing `jdoe@lab.local`, "Security device sign-in", PIN field, no password option | Demo-Walkthrough Step 1 |
| `01b-certutil-scinfo-yubikey-chain-validates.png` | WO02, 2026-06-16 | `certutil -scinfo` final lines — chain validates on Yubico YubiKey OTP+FIDO+CCID 0 reader, Smart Card Logon EKU 1.3.6.1.4.1.311.20.2.2, completed successfully | Demo-Walkthrough Step 3 supplement |
| `01c-certutil-scinfo-yubikey-container-info.png` | WO02, 2026-06-16 | `certutil -scinfo` container info — YubiKey key container details, key matching test | Demo-Walkthrough Step 3 supplement (deeper evidence) |
| `01d-certutil-scinfo-yubikey-cert-context-jane-doe.png` | WO02, 2026-06-16 | `certutil -scinfo` cert context — Subject `CN=Jane Doe, OU=SmartCard-Pilot, DC=lab, DC=local`, UPN binding evidence | Demo-Walkthrough Step 3 supplement |
| `01e-certutil-scinfo-public-key-matching-test.png` | WO02, 2026-06-16 | `certutil -scinfo` "Performing public key matching test" — proves keypair lives on card, signature verified | Demo-Walkthrough Step 3 supplement (deeper evidence) |
| `02-pin-entry-cert-subject.png` | Lab-WS01, 2026-06-01 15:05 | PIN prompt with `administrator@lab.local` and "Security device" visible | Demo-Walkthrough Step 2 |
| `02b-incorrect-pin-validation.png` | Lab-WS01, 2026-06-01 15:06 | "An incorrect PIN was presented" dialog - proves PIN validation works | Demo-Walkthrough Step 2 supplement |
| `03-pkinit-validation-table.png` | DC01 Security log, 2026-06-02 08:25 | Event 4768 fields annotated - labtech, Pre-Auth Type 16, LAB-CA, 10.10.20.30 (WO02), thumbprint match, Result 0x0 | Demo-Walkthrough Step 3 |
| `04-session-lock-on-card-removal.png` | WO02, 2026-06-16 14:13 | Windows 11 lock screen captured ~2 seconds after YubiKey removal; demonstrates `ScRemoveOption=1` GPO firing under the documented threshold | Demo-Walkthrough Step 4 |
| `06-pki-health-dashboard.png` | DC01, 2026-06-04 12:18:49 | `Monitor-PKIHealth.ps1` baseline run (no parameters) — every row gracefully `[SKIP]`, defensive-defaults proof | Demo-Walkthrough Step 6 supplementary |
| `06-pki-health-dashboard-parameterized.jpg` | DC01, 2026-06-04 13:59:25 | `Monitor-PKIHealth.ps1` parameterized run — real `[OK]` rows for CRL Endpoint and Issuing CA cert; ALL CHECKS PASSED | Demo-Walkthrough Step 6 |
| `07-scap-before-after-side-by-side.png` | Hyper-V host, 2026-06-03 | DC01 SCC All-Settings reports side by side: Before-MFA 44.95% (98 Pass / 120 Fail) vs After-MFA 42.66% (93 Pass / 125 Fail). Same target, same benchmark, only delta is the smart card enforcement | Demo-Walkthrough Step 7 |
| `08-scap-win11-stig-result.png` | SCC Summary Viewer, 2026-06-02 | WO02 scan: Microsoft_Windows_11_STIG, Score 37, 0 errors, 1 warning, links to All Settings / Non-Compliance / XCCDF / OVAL / OCIL / CKL | Demo-Walkthrough Step 7 supplement |

### Lessons-Learned / discovery evidence

| File | Source | Shows | Used By |
|---|---|---|---|
| `issue9-vsc-fallback-microsoft-virtual-smart-card.png` | WO02, 2026-06-16 14:07 | `certutil -scinfo` output revealing that "successful" enrollments silently landed on `Microsoft Virtual Smart Card 0` while the physical reader had no keyset. The forensic shot behind the Silent VSC Fallback discovery. | `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`, Demo-Walkthrough Step 3 failure-mode callout |

### Session evidence (enrollment journey, 2026-06-15 / 06-16)

These trace the v1.1 enrollment work that produced the headline captures. They support the runbook + manual walkthrough + lessons-learned docs rather than the live demo flow.

| File | Source | Shows |
|---|---|---|
| `session-2026-06-15-aduc-ou-layout.png` | DC01, 2026-06-15 | ADUC `lab.local` OU tree with `SmartCard-Pilot`, `Workstations`, computer objects |
| `session-2026-06-15-hirsch-read-only-error.png` | WO02, 2026-06-15 15:10 | "The smart card is read-only" on Hirsch uTrust — early evidence of Issue #9 trigger condition |
| `session-2026-06-16-new-tokenenrollment-ra-confirmation.png` | WO02, 2026-06-16 07:08 | `New-TokenEnrollment.ps1` RA + Issuer separation-of-duties confirmation prompt — NIST AC-5 narrative |
| `session-2026-06-16-smartcard-logon-enrollment-succeeded.png` | WO02, 2026-06-16 07:50 | Certificate Installation Results: Smartcard Logon STATUS Succeeded |
| `session-2026-06-16-hirsch-pin-init-prompt.png` | WO02, 2026-06-16 07:53 | Operator runbook PIN-init prompt + token-type detection for Hirsch |
| `session-2026-06-16-enrollment-agent-cardissuer-selected.png` | WO02, 2026-06-16 10:00 | Enrollment Agent wizard with `CardIssuer` EA cert selected for on-behalf-of issuance |
| `session-2026-06-16-enroll-on-behalf-jdoe.png` | WO02, 2026-06-16 10:02 | "Select a user → LAB\jdoe" — the on-behalf-of workflow in one frame |
| `session-2026-06-16-device-manager-labvsc-and-piv-card.png` | WO02, 2026-06-16 12:04 | Device Manager showing `LabVSC` and `Identity Device (NIST SP 800-73 [PIV])` side by side |
| `session-2026-06-16-yubikey-cannot-perform-operation-error.png` | WO02, 2026-06-16 12:08 | "The smart card cannot perform the requested operation" — pre-fix error state |
| `session-2026-06-16-ykman-piv-info-default-credentials-warning.png` | WO02, 2026-06-16 12:10 | "WARNING: Using default PIN! / PUK! / Management key!" — factory-default state proof |
| `session-2026-06-16-ykman-change-management-key-protect-generate.png` | WO02, 2026-06-16 12:11 | `ykman piv access change-management-key --protect --generate` showing PIN-protected mgmt key workflow |
| `session-2026-06-16-new-tokenenrollment-status-not-enrolled.png` | WO02, 2026-06-16 12:58 | `New-TokenEnrollment.ps1 -Mode Status` output: `jdoe@lab.local` NOT ENROLLED baseline |
| `session-2026-06-16-yubikey-piv-provisioning-step2-REDACTED.png` | WO02, 2026-06-16 10:49 | `New-YubiKeyToken.ps1` STEP 2 of 4 (Management Key) with YubiKey serial and AES-256 mgmt key BLACK-BOXED. **Redaction applied 2026-06-16** — original lives in gitignored `photos/` only |

### FIDO2 credential evidence (webauthn.io)

| File | Source | Shows |
|---|---|---|
| `webauthn-glenntest-yubikey-credential.png` | webauthn.io, 2026-06-15 14:01 | `glenntest-yubikey` credential card: device-bound passkey, transports `nfc`/`usb`, AAGUID anonymized |
| `webauthn-glenntest-hirsch-credential.png` | webauthn.io, 2026-06-15 14:03 | `glenntest-hirsch` credential card: device-bound passkey, transports `ble`/`nfc`/`usb`, AAGUID anonymized |
| `webauthn-glenntest-yubikey-direct-attestation.png` | webauthn.io, 2026-06-15 14:08 | Same YubiKey credential with `Attestation: direct` requested; AAGUID still all-zero (Windows anonymization) |
| `webauthn-glenntest-hirsch-direct-attestation.png` | webauthn.io, 2026-06-15 14:07 | Same Hirsch credential with `Attestation: direct` requested; AAGUID still all-zero (Windows anonymization) |

### Portfolio / reference evidence (pre-v1.1)

| File | Source | Shows | Used By |
|---|---|---|---|
| `evidence-enrollment-ceremony-success.png` | DC01, 2026-06-02 07:26 | `New-TokenEnrollment.ps1` Issuer phase completing for labtech - "Certificate enrolled successfully onto the token" | Portfolio evidence, AC-5 separation of duties |
| `troubleshoot-pre-kerberos-cert-fail.png` | WO02, 2026-06-02 07:28 | "Signing in with a security device isn't supported for your account" - before-state for the KerberosAuthentication cert fix | `TROUBLESHOOTING.md` reference |

---

## Still Pending

Only one slot in `Demo-Walkthrough.md` still needs a real capture:

| Slot | What to capture | Where | Blocker |
|---|---|---|---|
| 5 | **VPN connected** via EAP-TLS, no password prompt | WO02 after Step 7 | Depends on Phase 9 (Azure VPN Gateway) or Phase 9B (OPNsense) — VPN build not yet started |

Closed in v1.1 (2026-06-16): slots 1, 4, 6.

---

## Capture Guidelines

- **PNG, not JPG** - text stays crisp for portfolio review
- **Hide real names** - the lab account is `LAB\labtech`, not your real name
- **Hide hostnames outside lab.local** - if Agency or any production name shows, retake
- **No IPs outside `10.10.10.x` or `10.10.20.x`** - those are the only lab subnets
- **Stopwatch for slot 4** - phone stopwatch held next to monitor sells the "< 2 seconds" claim better than animation

---

## Naming Convention

`NN-short-description.png` where NN matches the Demo-Walkthrough.md step number it belongs to. Supporting evidence for the same step uses `NNa-`, `NNb-`, `NNc-`, etc. (e.g., `01b-` through `01e-` deepen the Step 3 cert-chain proof beyond the headline shot).

Use `evidence-` prefix for items that are portfolio-only (not part of the live demo flow).
Use `troubleshoot-` prefix for reference shots that document a problem/fix.
Use `session-YYYY-MM-DD-` prefix for raw session evidence supporting the runbook + lessons-learned narrative rather than the live demo.
Use `webauthn-` prefix for FIDO2 webauthn.io credential cards.
Use `issueN-` prefix for forensic shots behind a numbered Lessons-Learned finding.
Append `-REDACTED` to any filename where sensitive content (mgmt keys, serials, hostnames) has been black-boxed before publishing.

---

*Related: `..\Demo-Walkthrough.md`, `..\Lab-Kit\06-PhysicalEndpoint\Add-Physical-Laptop.md` (Step 5 screenshot checklist)*
