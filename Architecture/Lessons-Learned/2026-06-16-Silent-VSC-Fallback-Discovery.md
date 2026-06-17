# Silent TPM Virtual Smart Card Fallback During PIV Enrollment

**Author:** Glenn Byron
**Date discovered:** 2026-06-16
**Severity:** High — silent failure mode that defeats hardware-factor assurance
**Control mapping:** NIST SP 800-53 IA-2(11), IA-5(11), CM-6, AU-6 | CISA ZTMM Identity pillar (Hardware Authenticator)

---

## Summary

During PIV enrollment against a physical smart card whose PIV applet was not initialized with a usable management key, Windows did not surface an error. Instead, every enrollment silently completed against a TPM-backed Microsoft Virtual Smart Card (VSC) that was already provisioned on the workstation. Smart-card logon worked end-to-end, but the credential was never written to the physical token. Operators believed they had a hardware-bound credential; they did not.

This is a class of failure that converts a hardware-factor authentication design into a software-factor design without any visible signal. In a federal context that asserts AAL3 / phishing-resistant MFA based on a possession factor, this silently demotes the assurance level.

---

## Environment

| Item | Value |
|---|---|
| OS | Windows 11 Enterprise (workstation), Windows Server 2022 (Issuing CA) |
| PKI | Two-tier internal CA; Smartcard Logon + Enrollment Agent templates published |
| Smart card under test | Identive/HID uTrust FIDO2 FIPS card (PIV applet present, factory mgmt key rejected) |
| Pre-existing VSC | `Microsoft Virtual Smart Card 0` ("LabVSC") on the workstation TPM, previously used for an unrelated user |
| Enrollment paths attempted | `certmgr.msc` Personal → Request New Certificate; "Enroll on behalf of" via Enrollment Agent cert; CLI via `certreq` |

---

## What we observed

The enrollment wizard reported success on every attempt. A subsequent smart-card logon succeeded with the enrollee's PIN (`123456`, the VSC's initialized PIN — not the physical card's PIN). The Kerberos Pre-Auth event (4768, type 16 — PKINIT) appeared on the DC. By every observable indicator inside the GUI, hardware MFA was working.

Forensic check with `certutil -scinfo` told a different story:

- The physical uTrust reader reported `Microsoft Base Smart Card Crypto Provider: Missing stored keyset` and `Microsoft Smart Card Key Storage Provider: Missing stored keyset` — i.e., no key material had ever been written to the physical card.
- The `Microsoft Virtual Smart Card 0` reader held **every certificate that had been "enrolled":** two `labtech` certs, a `CardIssuer` cert, and the target `jdoe` cert (UPN `jdoe@lab.local`, chain validates, NT_AUTH OK).
- The "successful" smart-card logon had been satisfied by the VSC the entire time.

---

## Why it happened

Three conditions combined to produce a silent fallback:

1. **The physical card's PIV applet was present but unmanageable.** The uTrust card returned `Identity Device (NIST SP 800-73 [PIV])` to `certutil -scinfo`, so Windows considered it a valid PIV candidate. But the card had no keyset and the factory 3DES management key was rejected. Windows had no way to personalize it, and the uTrust minidriver assumes an already-personalized card.

2. **A pre-existing TPM VSC was available on the workstation.** When the enrollment path tried to generate a key, the Windows Smart Card Key Storage Provider chose the candidate that could accept a write — the VSC — and proceeded without error.

3. **No warning is emitted when fallback occurs.** The "smart card" UX layer treats the VSC and physical card as interchangeable smart card devices. There is no notification on the issuance path that the credential landed on a different factor than the operator chose.

The combination is what makes this dangerous. Either failure on its own — a broken physical card OR a stray VSC — would have been noticed during normal use. Together, they presented as success.

---

## How we detected it

`certutil -scinfo` enumerated every reader visible to the Windows smart card subsystem and printed the certs associated with each. That output revealed both:

- The physical reader had no keys and no certs.
- The Virtual Smart Card reader held all the certificates that had been "enrolled to the card."

Without `certutil -scinfo`, the failure would have been invisible. The enrollment wizard, certmgr.msc Personal store, and lock-screen smart-card logon all reported success.

---

## Detection script (proposed)

A scheduled check on every workstation that pulls smart card certs:

```powershell
# Detect-VSC-Fallback.ps1 (sketch)
# Flags any smart card cert sitting on a Virtual Smart Card reader,
# which usually indicates a fallback from a failed physical-card enrollment.

$readers = certutil -scinfo 2>&1 | Out-String
$vscCerts = ($readers -split 'Analyzing card in reader:') |
    Where-Object { $_ -match 'Microsoft Virtual Smart Card' -and $_ -match 'Subject:' }

if ($vscCerts) {
    Write-EventLog -LogName Application -Source 'PIVMonitor' -EventId 7301 `
        -EntryType Warning -Message "Smart card credential found on Virtual Smart Card reader. Possible silent fallback from failed physical-card enrollment. Investigate."
}
```

A simpler control: SIEM rule on Event 4768 (Kerberos PKINIT) correlated with cert issuance events from the CA — if a cert was issued for a user whose enrollment was supposed to land on a physical token, but the resulting logon authenticated against a VSC-issued cert, flag it.

---

## Compensating controls

The discovery surfaced four controls worth standardizing in any PIV-enabled environment:

1. **Run `certutil -scinfo` as a mandatory acceptance step at the end of every enrollment.** Operator runbook now requires it (see `Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md`). Compare the reader name in the output against the reader the operator intended to write to.

2. **Disable the TPM VSC before any physical-card enrollment session.** In Device Manager, disable the VSC reader for the duration of the ceremony, re-enable it afterward only if it has its own legitimate purpose. This forces Windows to fail loud rather than silently fall back.

3. **Test the physical card's PIV applet before issuing.** Run `ykman piv info` (YubiKey), `opensc-tool -l` + `piv-tool -A A:9B:03` (OpenSC), or vendor equivalent BEFORE the enrollment ceremony. If the card cannot accept a key write under the operator's known management key, abort — do not proceed to certmgr.

4. **Pin the issuance path to the intended reader.** For YubiKey, the working pattern was: reset PIV applet to factory defaults so the Yubico minidriver could manage the management key, then run Enroll-on-Behalf with the VSC explicitly disabled. This made fallback structurally impossible.

---

## Standing this up as a process control

The single most important fix is procedural, not technical: **the runbook now requires reader-level verification before the ceremony is closed.**

`Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md` requires the operator to:

1. Confirm the target reader name (e.g., `Yubico YubiKey OTP+FIDO+CCID 0`) BEFORE issuing.
2. Run `certutil -scinfo` after issuance and confirm the new cert appears on that exact reader.
3. Confirm `Microsoft Virtual Smart Card N` does NOT appear in the output during the ceremony.
4. Confirm the cert's Subject UPN matches the enrollee, not the issuer.

If any of these four checks fails, the enrolled cert is revoked at the CA and the ceremony restarts from a clean reset.

---

## Why this is a finding worth publishing

Most "smart card fallback" discussions in vendor and Microsoft documentation focus on the user-facing question of "what authenticator does Windows prefer at the lock screen." That misses the much more dangerous case: silent fallback during *issuance*, not at *authentication*. The credential is created on the wrong factor at the start. By the time anyone observes a successful logon, the trail is cold.

For a federal accreditation that asserts hardware-bound PIV credentials, this is the kind of finding that would not survive a real assessment. The fix is not a single setting — it is a procedural change baked into the operator runbook and an acceptance check on every workstation.

---

## Mapping to controls

| Control | Relevance |
|---|---|
| NIST SP 800-53 IA-2(11) | Acceptance of PIV credentials — the asserted hardware factor must actually be hardware. |
| NIST SP 800-53 IA-5(11) | Hardware token authenticator — credentials must be bound to the asserted hardware. |
| NIST SP 800-53 CM-6 | Configuration management — disabling VSC for the issuance ceremony is a documented configuration control. |
| NIST SP 800-53 AU-6 | Audit review — `certutil -scinfo` is the acceptance signal that gets recorded in the operator log. |
| CISA ZTMM Identity pillar | Authenticator strength is moot if the credential silently lands on a software authenticator. |
| FIPS 201-3 §4.2 | PIV credential issuance binding the credential to a specific PIV authenticator. |

---

## Status

| Item | State |
|---|---|
| Runbook acceptance check added | ✅ `Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md` |
| YubiKey enrollment validated against this control | ✅ `certutil -scinfo` confirms `jdoe` cert on `Yubico YubiKey OTP+FIDO+CCID 0` reader; chain validates to LAB-CA |
| Detection script | ⏳ Sketched in this document; production implementation queued |
| Lesson encoded in `Card-Test-Matrix.md` | ✅ Hirsch n=2 row documents the unmanageable-applet condition that triggered the fallback |

---

## Related documents

- `Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md` (RUNBOOK-ICAM-001) — operator runbook with the four-point acceptance check
- `Lab-Kit/Reference/Card-Test-Matrix.md` — hardware behavior matrix; Hirsch row documents the trigger condition
- `Architecture/Lessons-Learned/2026-06-16-CAC-Enrollment-Session.md` — full session log with raw forensic output
- `Architecture/RMF-Templates/SSP-Template.md` — IA-2(11), IA-5(11), CM-6 mappings
