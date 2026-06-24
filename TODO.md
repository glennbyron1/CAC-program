# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** June 17, 2026 (post-v1.2 ship)

Living task list for the CAC/PIV ICAM portfolio project.
✅ Complete · ⬜ Needs hands-on work · ⏳ In progress

---

## Security Posture

- ✅ **Repo is public** (2026-06-03), with sensitive values scrubbed at push time via `Scrub-Repo.ps1` reading `.scrub-patterns.local.json`.
- ✅ **Lab admin password rotated** (2026-06-15) — defense-in-depth response following forensic verification of the public-window exposure. Treated as if leaked even though no direct evidence of malicious cloning was found. New value lives in `.scrub-patterns.local.json` and is replaced with `<LAB-ADMIN-PASSWORD>` at push time. Methodology + analysis documented in [`Architecture/Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md`](Architecture/Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md).
- ✅ **Pre-add scan workflow** — `security/scripts/Scan-LocalRepo.ps1` runs against new files before they're committed.
- ✅ **10 patterns all `[CLEAN]`** verified via `Scan-LocalRepo.ps1` after fresh-clone rebuild (Stale Clone exercise outcome). Per-pattern `[CLEAN]/[LEAK]` status block shows every pattern was visibly checked.
- ✅ `.scrub-patterns.local.json` cleaned up — duplicate-case keys removed, dotless subnet pattern removed. Scanner parses via `ConvertFrom-Json` cleanly with regex fallback.
- ✅ **Stale-clone incident handled safely** (2026-06-13) — merge aborted on secondary Windows clone before any compromised state was pushed; forensic verification via Events API + Wayback Machine + Traffic dashboard confirmed bounded exposure window. Lessons-learned doc published.

---

## Milestones

- ✅ **GitHub repo topics added** — `identity-management`, `pki`, `smart-card`, `fido2`, `active-directory`, `certificate-authority`, `nist-800-53`, `fips-201`, `zero-trust`, `icam`, `ad-cs`, `powershell`, `disa-stig`, `hyper-v`, `rmf`, `cac`
- ✅ **v1.0 pushed** (2026-06-03) — two-tier PKI + smart card MFA on physical endpoint + SCAP evidence (DC01 42.66% / WS01 42.20% / WO02 37.00%) + Phase 8 Zero Trust extension (8 full scripts + 13 scaffolds + Demo-Walkthrough-ZT.md)
- ✅ **GitHub release notes published** (2026-06-04) — v1.0 release notes posted on the `v1.0` tag covering PKI, smart card MFA, SCAP evidence, ZT extension, with card-blocked items called out as deferred to v1.1.
- ✅ **v1.1 shipped (2026-06-16)** — slot 1 + slot 4 + slot 1b cert chain. `Card-Test-Matrix.md` PIV row filled in. Silent VSC Fallback discovery published as Lessons-Learned. Enrollment kit (4 scripts + scripted runbook + manual GUI walkthrough + session log) staged. Scrub-Repo.ps1 hardening (two bugs caught by -WhatIf). Release notes published on the v1.1 tag.
- ✅ **v1.2 shipped (2026-06-17)** — **Slot 5 closed: Azure VPN with cert auth via YubiKey** (same physical token unlocks AD AND Azure VPN). Phase 9 fully built: cost guardrail, VNet + GatewaySubnet, VPN Gateway VpnGw1, LAB-CA cert uploaded as Azure trust root, jdoe's slot 9a cert authenticates EAP-TLS tunnel, P2S assigned 172.16.0.2. Three Azure VPN docs consolidated into one canonical `Architecture/Azure-VPN-Guide.md` (ARCH-ICAM-013). PKI architecture discovery: design says two-tier, deployed is single-tier (LAB-CA as root) — captured honestly in the guide. Install pitfall + fix path (`VpnProfileSetup.ps1` from elevated PowerShell + Automatic tunnel type) documented.

---

## Forward-looking (queued, not blocking)

- ✅ **`Architecture/Lab-Topology.md` — DONE 2026-06-17** (ARCH-ICAM-014). Documents the deliberate air-gapped lab topology: dumb switch between Hyper-V host and WO02; host has Wi-Fi for staging only (not bridged to lab segment); lab segment has no internet; transfers staged on host then pushed into the lab via Hyper-V Enhanced Session / PowerShell Direct / USB. Physical + logical network diagrams (ASCII). Maps to NIST SC-7 (boundary protection), AC-4 (information flow enforcement), CM-7 (least functionality), SC-32 (system partitioning), PE-3 (physical access), SC-39 (process isolation), and CISA ZTMM Networks pillar. Frames the design as a scaled-down version of the "staging-host pattern" used in classified environments — including the deliberate choice of a dumb unmanaged switch over a VLAN-segmented managed switch (smaller attack surface, defensible to a reviewer in one sentence).
- ⬜ **Repo cleanup / consolidation pass** — sweep the repo for stale docs, consolidate where helpful, archive anything superseded. The doc count has grown substantially across v1.0 → v1.1 (Frameworks-Considered, Card-Test-Matrix, Lessons-Learned, Live-Servers, Tools-Kit, SCAP workflow, Phase 8 ZT extension, etc.). Worth a pass once card testing closes to verify nothing is orphaned, every top-level doc has a clear purpose, and the README "What's in the Repo" table matches reality.

---

## Lab Discipline (scope boundaries)

The lab is now in **converging mode**, not creating mode. Finish what is in flight. The following discipline rules govern what does and does not get added:

- **8-tool suite is frozen.** No new tools, no 10th repo, no new phases chasing "completeness." Finishing > creating.
- **Don't chase SCAP score to 90%.** The **delta** from hardening is the portfolio value — not the absolute number.
- **Phase 9B (on-prem VPN appliance — OPNsense) is OPTIONAL.** Azure VPN (v1.2) closes the cloud-VPN story end-to-end with the same physical YubiKey doing AD logon AND tunnel auth. OPNsense would close an on-prem appliance story that the WatchGuard guide (`Architecture/WatchGuard-IKEv2-VPN-Guide.md`) already covers in design. Not planned. Re-evaluate only if a specific defense-contractor role requires demonstrating an air-gapped / non-cloud appliance build.
- The 13 Phase 8 ZT scaffolds are fine as "designed, not built" — portfolio-positive as designs.
- All work-lab docs stay **generic** — no employer-identifying details public.
- Hardware behavior in `Card-Test-Matrix.md` — no vendor pricing, roadmap, or commercial-engagement detail.

---

## One-Time Setup ✅ Complete

- ✅ `.scrub-patterns.local.json` created with real identifiers
- ✅ GitHub email privacy enabled
- ✅ PowerShell push credentials fixed
- ✅ Git history rewritten — Gmail removed from all commits
- ✅ Repo verified clean — Scrub-Repo.ps1 run before all pushes

---

## CI/CD & Automation ✅ Complete

### GitHub Actions
- ✅ Secret & sensitive file scan
- ✅ PowerShell lint (PSScriptAnalyzer)
- ✅ CodeQL SAST
- ✅ Dependency review
- ✅ Gitleaks — full git history secret scan (weekly + every push)

### Ansible Playbooks
- ✅ `Lab-Kit/Ansible/windows-stig-hardening.yml` — STIG remediation (8 sections)
- ✅ `Lab-Kit/Ansible/ad-health-check.yml` — stale accounts, privileged groups, smart card enforcement, scforceoption guard
- ✅ `Lab-Kit/Ansible/cert-expiry-report.yml` — Root CA, Issuing CA, user certs, OCSP, CRL expiry

---

## Lab Execution — SCAP Scans ✅ Complete

- ✅ Before-MFA SCAP scan — DC01: **44.95%** (CAT I fail: 9, CAT II: 105, CAT III: 6)
- ✅ Before-MFA SCAP scan — WS01: **42.20%** (CAT I fail: 9, CAT II: 111, CAT III: 6)
- ✅ Before-MFA results staged in `Compliance-Reports/Before-MFA/`
- ✅ Smart card logon confirmed working
- ✅ After-MFA SCAP scan — DC01: **42.66%** (CAT I fail: 9, CAT II: 110, CAT III: 6)
- ✅ After-MFA SCAP scan — WS01: **42.20%** (CAT I fail: 9, CAT II: 111, CAT III: 6)
- ✅ After-MFA results staged in `Compliance-Reports/After-MFA/`
- ✅ `Compliance-Reports/README.md` scoring table updated with real numbers

### Optional Compliance Evidence

- ⬜ Nessus Essentials — credentialed scan (free, up to 16 IPs)
- ⬜ STIG Viewer — open .ckl files, review CAT I findings, document false positives
- ⬜ **CIS Workbench reference materials** — register at [workbench.cisecurity.org](https://workbench.cisecurity.org/) (free for individuals); download the Windows Server 2022 + Windows 11 CIS Benchmarks for reference alongside DISA STIG. Reference only — not a parallel hardening pass (per Lab Discipline). Backs the framework comparison in [`Architecture/Frameworks-Considered.md`](Architecture/Frameworks-Considered.md) and the cross-reference table in `SSP-Template.md` § 6.7.
- ✅ PKI health check baseline — `Monitor-PKIHealth.ps1` run 7x on 2026-06-04 (audit log + 12:18:49 dashboard screenshot staged in `Compliance-Reports/PKI-Health/2026-06-04/`)

---

## RMF Templates ✅ Populated

- ✅ `Architecture/RMF-Templates/SAR-Template.md` — real scores, controls assessment, risk summary
- ✅ `Architecture/RMF-Templates/POAM-Template.md` — 18 CAT I / 221 CAT II / 12 CAT III tracked
- ✅ `Architecture/RMF-Templates/SSP-Template.md` — hostnames, roles, scan results, ATO pending
- ✅ `Architecture/RMF-Templates/Annual-STIG-Rescan-SOP.md` — 2026 baseline row populated

### Still Needs Input

- ✅ **AO name and signature** — filled in SSP and SAR (Glenn Byron, System Owner / Lab Program Manager, Self-Assessed Lab)
- ⬜ **Nessus Essentials scan** — adds vulnerability evidence; results go in SAR § 7 and POAM
- ⬜ **IIS STIG assessment** — CRL/AIA server; referenced as pending in all four templates
- ✅ **STIG Viewer CAT I review — DONE 2026-06-17** — all 22 unique CAT I findings across DC01 / WS01 / WO02 documented in `Architecture/RMF-Templates/POAM-Template.md` grouped by category (AutoPlay×6, Windows Installer Always Install Elevated×2, WinRM Basic auth×4, Anonymous share enumeration×2, LM auth level×2, AD data files permissions×1, Win11-specific×5). All real findings — none are false positives. Disposition: 18 queued for Ansible remediation, 1 manual review (AD data files), 2 risk-accept candidates (BitLocker disk encryption + pre-boot PIN on WO02), 4 operational no-op but remediate (WinRM Basic auth — lab uses Kerberos). Confirmed smart-card STIG rules (`WN22-SO-000120` Interactive logon require smart card; `WN22-CC-000080` smart card removal behavior) **passed** the scans — identity controls IA-2 / AC-5 / IA-2(11) fully satisfied. Risk Acceptance Register seeded with RA-001 (BitLocker disk) and RA-002 (BitLocker PIN), pending Glenn-as-AO sign-off.

### Multi-Framework Awareness

- ✅ **`Architecture/Frameworks-Considered.md`** — short doc explaining why DISA STIG was chosen for this lab and noting CIS Benchmarks as the equivalent for non-DoD / commercial deployments. Lists CMMC, NIST 800-171, ISO 27001, CJIS, HITRUST, PCI DSS as adjacent frameworks worth knowing.
- ✅ **CIS Controls v8 cross-reference added to SSP-Template.md § 6.7** — maps each implemented NIST 800-53 control to its CIS Controls v8 equivalent. Shows framework portability without running a parallel CIS hardening pass.
- (Not doing) Separate CIS Benchmark hardening pass — would violate "8-tool suite frozen" discipline. CIS is mapped, not duplicated.

---

## Physical Laptop (WO02) — Add to Lab

Guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`

- ✅ Windows 11 confirmed
- ✅ TPM 2.0 confirmed — VSC ready
- ✅ External virtual switch created — DC01 dual-NIC (10.10.10.0/24 LabInternal + 10.10.20.0/24 External)
- ✅ Domain-joined to lab.local — computer object at `CN=WO02,OU=Workstations`
- ✅ Smart card GPO applied (`scforceoption=1`, `ScRemoveOption=1`, `InactivityTimeoutSecs=900`)
- ✅ Virtual Smart Card created via `tpmvscmgr.exe`
- ✅ VSC certificate enrolled for `LAB\labtech` via `New-TokenEnrollment.ps1` (RA + Issuer ceremony, AC-5 satisfied)
- ✅ Smart card logon confirmed working on real hardware (RDP to 10.10.20.30, PIN entry, desktop reached)
- ✅ **Event 4768 Pre-Auth Type 16 captured** — PKINIT confirmed at protocol level (logged in `Lab-Kit/LAB-BUILD-CHANGELOG.md`)
- ✅ Run SCAP SCC scan with Windows 11 STIG benchmark — **DONE 2026-06-02** — WO02 against `Microsoft_Windows_11_STIG-2.3.9` (MAC-1 Classified profile): **37.00%** compliance (13 CAT I open, 122 CAT II, 8 CAT III). Results staged in `Compliance-Reports/Laptop/After-SmartCard/2026-06-02_104513/`
- ✅ **Test VPN from physical laptop (EAP-TLS, no password) — DONE 2026-06-17 (v1.2)** — WO02 connected to Azure P2S VPN `vnet-cac-lab-phase9` using jdoe's YubiKey-resident slot 9a cert. EAP-TLS authentication via Lab-CA chain. No password prompt anywhere. Slot 5 captured: `Screenshots/05-vpn-azure-eap-cert-auth-no-password.png` (+ `05b` ipconfig 172.16.0.2 proof + `05c` config caption). Full build: `Architecture/Azure-VPN-Guide.md` (ARCH-ICAM-013).
- ✅ Checkpoint taken — `06-WO02-SmartCard-Working`

---

## Portfolio Finalization

- ✅ Portfolio Word docs updated with all three After-MFA scores (DC01 42.66% / WS01 42.20% / WO02 37.00%) — "SCAP Compliance Snapshot" section + results table + interpretation paragraph + source citation added to `CAC-Program-Showcase-GlennByron.docx` and `Federal_Upgrade_Path.docx` (2026-06-03)
- ✅ `SCAP-Workflow-QuickRef.md` promoted from `Dispatch/` to `Lab-Kit/05-Compliance/` — stale `192.168.1.10` fixed to `10.10.10.10` / `Lab-DC01`. Docker `scap-summary` moved to "Optional Enhancements" at bottom (deferred until DC hardening pass)
- ✅ **Screenshots — 8 of 8 staged (all slots closed)**
    - ✅ Slot 1 — `01-lockscreen-smartcard-only.png` (jdoe@lab.local, Security device sign-in, no password field)
    - ✅ Slot 1b — `01b-certutil-scinfo-yubikey-chain-validates.png` (cert chain validates on physical YubiKey, Smart Card Logon EKU)
    - ✅ Slot 2 — `02-pin-entry-cert-subject.png` (PIN prompt)
    - ✅ Slot 2b — `02b-incorrect-pin-validation.png` (incorrect PIN dialog)
    - ✅ Slot 3 — `03-pkinit-validation-table.png` (Event 4768 annotated)
    - ✅ Slot 4 — `04-session-lock-on-card-removal.png` (lock screen ~2 seconds after card pull)
    - ✅ **Slot 5 (v1.2) — `05-vpn-azure-eap-cert-auth-no-password.png`** (Azure VPN P2S Connected, cert auth via same YubiKey, IPv4 172.16.0.2 from P2S pool). Supplements: `05b-vpn-ipconfig-172-16-0-2.png` (tunnel proof) + `05c-vpn-caption-azure-p2s-eap-tls.png` (config caption).
    - ✅ Slot 6 — `06-pki-health-dashboard.png` (Monitor-PKIHealth.ps1 on Lab-DC01, 2026-06-04 12:18:49, ALL CHECKS PASSED)
    - ✅ Slot 7 — `07-scap-before-after-side-by-side.png` (DC01 44.95% → 42.66%)
    - ✅ Slot 8 — `08-scap-win11-stig-result.png` (SCC Summary Viewer, WO02)
    - ✅ *(v1.1 polish — done early)* parameterized PKI health run captured (13:59:25) — real `[OK]` rows for CRL Endpoint (expires 2026-12-05) + Issuing CA cert (expires 2031-05-26). `Screenshots/06-pki-health-dashboard-parameterized.jpg` is the primary slot 6 image; baseline `[SKIP]` run kept as supplementary.
    - ✅ Supporting evidence (16 session shots + 4 webauthn credential cards + 3 Phase 9 slot-5 captures) — see `Screenshots/` for full set
- ⬜ Run full Ansible STIG hardening pass — would push SCAP scores up significantly (~42.66% → ~70%+). **Deliberately deprioritized** per Lab Discipline: "delta from hardening is the portfolio value, not the absolute number." The existing Before/After-MFA delta is real evidence; absolute number isn't blocking. Run any time; doesn't need its own tag.
- ✅ Final `Scrub-Repo.ps1 -WhatIf` pass before any push — proven across v1.0, v1.1, v1.2 cycles (clean every time; repo is clean by construction).

---

## Card Hardware Testing — ongoing (YubiKey + Hirsch closed in v1.1; other cards still in queue)

- ✅ Test hardware received: YubiKey 5 NFC units + Hirsch uTrust FIDO2 FIPS Cards + additional smart cards from other vendors
- ✅ `certutil -scinfo` on Hirsch card — PIV applet confirmed present (`Identity Device (NIST SP 800-73 [PIV])`)
- ✅ PIV enrollment on YubiKey 5 NFC — succeeded via `New-YubiKeyToken.ps1` (Enroll-on-Behalf path with Yubico minidriver); cert + chain verified by `certutil -scinfo`
- ✅ FIDO2 on YubiKey via webauthn.io — device-bound passkey, transports `nfc`/`usb`
- ✅ FIDO2 on Hirsch card via webauthn.io — device-bound passkey, transports `ble`/`nfc`/`usb`
- ✅ Smart card logon to `lab.local` with YubiKey — jdoe logs into WO02 with card + PIN under `SmartcardLogonRequired=True`
- ✅ Hirsch PIV (n=2) — declared NO-GO; factory 3DES management key rejected on both cards. Vendor personalization tool + per-card mgmt key required. FIDO2 still works.
- ✅ **Slot 1 captured** — `01-lockscreen-smartcard-only.png`
- ✅ **Slot 1b captured** — `01b-certutil-scinfo-yubikey-chain-validates.png` (cert chain proof)
- ✅ **Slot 4 captured** — `04-session-lock-on-card-removal.png` (~2-second lock confirmed)
- ✅ **Slot 5 — VPN EAP-TLS from WO02 — DONE 2026-06-17 (v1.2)** — Azure P2S VPN cert auth via YubiKey closed slot 5. See `Architecture/Azure-VPN-Guide.md`.
- ✅ `Lab-Kit/Reference/Card-Test-Matrix.md` PIV + FIDO2 rows filled in; Hirsch NO-GO finding documented
- ✅ **`Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`** — discovered & published: silent fallback to TPM Virtual Smart Card during enrollment when physical PIV applet is unmanageable. Detection methodology + compensating controls documented. Original DevSecOps finding.
- ✅ **Enrollment kit staged** — `New-LabUser.ps1`, `New-TokenEnrollment.ps1`, `New-YubiKeyToken.ps1`, `Deploy-ScriptsToDC.ps1` in `Lab-Kit/03-DomainController/`; `RUNBOOK-YubiKey-Enrollment.md` (RUNBOOK-ICAM-001) in `Lab-Kit/Reference/`
- ✅ **Session log** — `Architecture/Lessons-Learned/2026-06-16-CAC-Enrollment-Session.md` (scrubbed)
- ✅ Update `Federal_Upgrade_Path.docx` with FIPS 140-3 / AAL3 / TAA evidence from Hirsch card (vendor materials, not lab-tested)
- ✅ (Optional) Real AAGUID values via `ykman fido info` for both cards (webauthn.io anonymizes them)

### Cards closed (v1.1)

- ✅ **YubiKey 5 NFC** — PIV end-to-end (Enroll-on-Behalf + Yubico minidriver), FIDO2 (device-bound passkey, nfc/usb), smart-card logon to `lab.local` under `SmartcardLogonRequired=True`. Reference design for any future YubiKey-line testing.
- ✅ **Hirsch uTrust FIDO2 FIPS (n=2)** — FIDO2 works; PIV declared NO-GO (factory 3DES mgmt key rejected on both cards; requires vendor personalization tool + per-card mgmt key).

### Cards still to test (queued)

- ⬜ **GIDS PKI smart cards** — Generic Identity Device Specification; Windows includes a built-in GIDS minidriver, so PIV enrollment may work without a vendor-specific minidriver install (would be a different procurement story than Hirsch's). Verify: PIV applet present, factory mgmt key state, GIDS minidriver behavior during Enroll-on-Behalf, FIDO2 if applicable.
- ⬜ **Additional smart-card form factors in queue** — various PKI implementations TBD; add a row to `Card-Test-Matrix.md` per card tested.
- ⬜ **(Optional) YubiKey 5 NFC FIPS SKU** — separate procurement from the tested 5 NFC. Higher-assurance variant; would validate the same workflow against a FIPS 140-3 Level 2 module. Not on hand; would only add if there's a specific reason (e.g., federal target environment requires FIPS).
- ⬜ Any future card form factors as they enter the lab — same test pattern: detection via `certutil -scinfo`, FIDO2 via webauthn.io, PIV via Enroll-on-Behalf, smart-card logon to `lab.local`, Azure VPN EAP-TLS (Phase 9 path now proven in v1.2).

**Procurement-question to evaluate each new card against early:** can the card be brought to a known-management-key state using off-the-shelf tooling (ykman, OpenSC, GIDS minidriver), or does it require vendor-specific software + per-card management key? The Hirsch uTrust NO-GO finding turned on exactly this question.

---

## Phase 8 — Zero Trust Extension ✅ Shipped in v1.0

8 full implementations · 13 scaffolds · 2 docs · 21 scripts total in `Lab-Kit/07-ZeroTrust/`. **The 13 scaffolds are intentionally left as "designed, not built" — portfolio-positive as designs; not chasing build for build's sake.**

- Design: [`Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md`](Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md)
- Run order + per-script detail: [`Lab-Kit/07-ZeroTrust/README.md`](Lab-Kit/07-ZeroTrust/README.md)
- Live demo script: [`Lab-Kit/07-ZeroTrust/Demo-Walkthrough-ZT.md`](Lab-Kit/07-ZeroTrust/Demo-Walkthrough-ZT.md)

**Pending follow-ons (queued as v1.3 candidate — these two go together):**

- ⬜ **Snapshot Lab-DC01 + run the 8 shipped Phase 8 ZT scripts to operationalize** — moves Phase 8 from "8 full scripts shipped as designs in v1.0" to "8 scripts shipped AND run on the DC with logged results." 8.1.4 already deployment-tested in v1.0; lessons #10-#11 captured. This closes the "designed not built" gap on the operational side.
- ⬜ **Extend `Stage-Reports.ps1` with Before-ZT / After-ZT delta** — small script update that closes the evidence loop for the operationalization above. Bundle WITH the operationalization in v1.3 so the Before-ZT baseline is captured before the scripts run and After-ZT is captured after.

**v1.3 framing:** Phase 8 ZT extension transitions from "designed" to "operational" with full Before/After-ZT evidence. Same Before/After delta pattern as v1.0's SCAP scans (and matches the "delta is the portfolio value" discipline). Pairs nicely with Phase 9.1 Entra baseline + Phase 9.3 Conditional Access if you want a meatier v1.3 release — but the standalone Phase 8 operationalization is a clean v1.3 on its own.

---

## Phase 9 — Azure Cloud VPN + Conditional Access ⏳ Partially Built

Build guide: `Architecture/Azure-VPN-Guide.md` (ARCH-ICAM-013)
Requires: Azure for Students + free M365 Developer tenant.

- ✅ 9.0 — Cost guardrail + resource group (v1.2: `rg-cac-lab-phase9` with $20/month budget alert; teardown via `Remove-AzResourceGroup` after each session)
- ✅ 9.1 — Entra tenant + test users + MFA enrollment (M365 Developer tenant; queued)
- ✅ **9.2 — Azure P2S VPN Gateway authenticated by Issuing CA certs (v1.2 — slot 5 deliverable)** — VpnGw1 deployed, LAB-CA root cert uploaded as Azure trust anchor, jdoe's slot 9a YubiKey cert authenticated EAP-TLS tunnel, P2S client assigned 172.16.0.2. Same physical card unlocks AD AND Azure VPN.
- ✅ 9.3 — Conditional Access policies (MFA + compliant device)
- ✅ 9.4 — Device compliance signal (Entra join + Intune)
- ✅ 9.5 — Sign-in logs + detections
- ✅ 9.6 — Teardown discipline (v1.2: tearing down via `Remove-AzResourceGroup -Force -AsJob` proven; documented in build guide Step 11)

---

## Phase 9B — On-Prem VPN Appliance (OPNsense) — ⏸️ OPTIONAL, NOT PLANNED

Design exists at `Architecture/Roadmap/CAC_PIV_Phase9B_OnPrem_VPN_Appliance.md`.
Requires: Dell 3080 Micro #2 + OPNsense.

**Rationale for not building:** Azure VPN (v1.2) closes the cloud-VPN story end-to-end. The WatchGuard IKEv2 VPN guide (`Architecture/WatchGuard-IKEv2-VPN-Guide.md`) covers the on-prem appliance pattern in design. OPNsense would be a third VPN implementation of the same trust chain — diminishing portfolio return for the effort.

**When to revisit:** only if pursuing a specific role that requires demonstrating an air-gapped / non-cloud appliance build with hands-on syslog forwarding into a SIEM (would also satisfy CySA+ Blue Team lab requirements). Until then, the design doc is the portfolio artifact and that's enough.

Sub-phases (kept for reference if ever activated):
- ⏸️ 9B.1 — Hardware + network prep
- ⏸️ 9B.2 — OPNsense base install + hardening
- ⏸️ 9B.3 — Issue server + client certs from your Issuing CA
- ⏸️ 9B.4 — VPN profile, cert-auth test, negative test (revoked cert)
- ⏸️ 9B.5 — Syslog forwarding to Splunk (ties into CySA+ lab)
- ⏸️ 9B.6 — Validation + evidence

---

## Phase Summary

| Phase | Status |
|-------|--------|
| 1 — Foundation & Architecture | ✅ Complete |
| 2 — Core Automation Scripts | ✅ Complete |
| 3 — Compliance & Regulatory Docs | ✅ Complete |
| 4 — Lab Execution (SCAP Scans) | ✅ Complete (DC01 + WS01 + WO02 all scanned) |
| 5 — RMF Authorize | ✅ Templates populated · AO signature pending |
| 6 — Advanced Automation | ✅ Complete |
| 7 — Portfolio Finalization | ✅ All 8 slots captured (slot 5 closed in v1.2) · Portfolio docs ✅ |
| 8 — Zero Trust Extension | ✅ 8 full scripts + 13 scaffolds + Demo-Walkthrough-ZT.md shipped in v1.0 |
| 9 — Azure Cloud VPN | ✅ 9.0 + 9.2 + 9.6 ✅ (v1.2) · 9.1/9.3/9.4/9.5 designed not built |
| 9B — On-Prem VPN Appliance (OPNsense) | ⏸️ Optional · design only · not planned (Azure VPN closes the VPN story; WatchGuard guide covers on-prem pattern in design) |
| Card Hardware Testing | ⏳ YubiKey ✅ · Hirsch uTrust NO-GO ✅ · GIDS + additional cards in queue |

---

## Recent Wins (2026-06-17 — v1.2 ship)

- ✅ **Phase 9 Azure VPN built end-to-end (slot 5 closed)** — Resource group with $20/month budget alert (Step 1), VNet `10.20.0.0/16` with `GatewaySubnet` `10.20.255.0/27` (Step 2), VpnGw1 VPN Gateway with Standard Static public IP (Step 3, ~40 min deploy), LAB-CA cert exported from Lab-DC01 via PowerShell Direct (Step 4), jdoe cert verified on YubiKey (Step 5), P2S configured with LAB-CA Base64 + IKEv2/OpenVPN tunnel types + `172.16.0.0/24` client pool (Step 6), `VpnProfileSetup.ps1` install (Step 7 — bypassed the GUI installer's smart-card-required elevation block + the Azure VPN Client app's YubiKey-cert enumeration limitation), connection with cert picker → `CN=Jane Doe` → YubiKey PIN → tunnel up with `172.16.0.2` assigned (Steps 8-9), three slot 5 screenshots captured (Step 10), full teardown via `Remove-AzResourceGroup -Force -AsJob` (Step 11). Single-session deploy → test → teardown cost: ~$0.40 in gateway hours.
- ✅ **Azure VPN documentation consolidated** — 3 source docs (`Azure-VPN-Lab-Guide.md`, `Phase9-Azure-VPN-Build-Guide.md`, `Roadmap/CAC_PIV_Phase9_Azure_VPN_ConditionalAccess.md`) → one canonical `Architecture/Azure-VPN-Guide.md` (ARCH-ICAM-013, ~570 lines). 7 cross-references updated across Demo-Walkthrough, CSET-Assessment-Guide, SSP-Template, TODO. Zero broken refs after consolidation.
- ✅ **PKI architecture discovery — designed two-tier, deployed single-tier** — Lab-DC01's Trusted Root store has `CN=LAB-CA` as self-signed (Subject == Issuer). The `CN=Lab Root CA` cert exists (10-year, valid 2026→2036) but has `basicConstraints CA:TRUE, pathlen:0` which per RFC 5280 means it can only sign end-entity certs — so it cannot have signed LAB-CA as a sub-CA. The deployed PKI is operationally single-tier with LAB-CA as the trust anchor. Documented honestly in `Architecture/Azure-VPN-Guide.md` as "designed vs deployed delta" — future remediation queued.
- ✅ **Three slot 5 screenshots staged + embedded in Demo-Walkthrough** — `05-vpn-azure-eap-cert-auth-no-password.png` (headline: jdoe@lab.local, Connected, duration 3:59), `05b-vpn-ipconfig-172-16-0-2.png` (tunnel-up proof), `05c-vpn-caption-azure-p2s-eap-tls.png` (config caption). Demo-Walkthrough Step 5 "📸 Pending capture" placeholder replaced with the three captures + portfolio-grade "What to say" narrative.
- ✅ **Same physical YubiKey now unlocks AD AND Azure VPN** — one slot 9a cert, two authentication contexts: Kerberos PKINIT (Event 4768 Pre-Auth Type 16) for AD logon, EAP-TLS for Azure P2S. The credential never leaves the hardware token; both authentications validate the same chain to LAB-CA. This is the v1.2 differentiator and the headline answer to "tell me about something you built."

---

## Recent Wins (2026-06-16)

- ✅ **YubiKey PIV enrollment end-to-end** — jdoe enrolled on physical YubiKey 5 NFC via `New-YubiKeyToken.ps1` + Enroll-on-Behalf, logged into WO02 with card + PIN under full smart-card-required enforcement.
- ✅ **Silent VSC Fallback discovery published** — `Architecture/Lessons-Learned/2026-06-16-Silent-VSC-Fallback-Discovery.md`. Original DevSecOps finding: smart card enrollment can silently land on a TPM Virtual Smart Card when the physical PIV applet is unmanageable, defeating the hardware-factor assurance claim. Detection methodology, compensating controls, and four-point operator acceptance check documented. Maps to NIST IA-2(11), IA-5(11), CM-6, AU-6 and CISA ZTMM Identity pillar.
- ✅ **Enrollment kit staged** — 4 PowerShell scripts (`New-LabUser.ps1`, `New-TokenEnrollment.ps1`, `New-YubiKeyToken.ps1`, `Deploy-ScriptsToDC.ps1`) + operator runbook (`RUNBOOK-YubiKey-Enrollment.md`, RUNBOOK-ICAM-001) + scrubbed session log. Scripts include fixes for: strict-mode null guards, AES-256 vs AES-192 byte sizing, RFC 4514 CSR subject format, certreq template attribute, hashtable splatting, ykman stderr handling on PS 5.1.
- ✅ **Hirsch uTrust FIDO2 FIPS PIV declared NO-GO (n=2 cards)** — factory 3DES management key rejected on both; vendor personalization tool + per-card mgmt key required. FIDO2 applet on same cards works fine. Documented in `Card-Test-Matrix.md`.
- ✅ **Card-Test-Matrix.md PIV + FIDO2 rows filled in** — detection results, FIDO2 webauthn.io evidence (device-bound passkey, transport differences, AAGUID anonymization), PIV enrollment workflow, observations.
- ✅ **Demo-Walkthrough.md slots 1 / 1b / 4 captured and embedded** — lock screen smart-card-only, certutil -scinfo chain validates, 2-second lock on card removal. Three "📸 Pending capture" placeholders closed.
- ✅ **Screenshot triage** — 31 raw screenshots → 24 keepers staged in `Screenshots/` with named slot filenames; 1 redacted to remove YubiKey serial + AES-256 management key; 7 deleted as duplicates/empty states.
- ✅ **`.scrub-patterns.local.json` extended** — added YubiKey management key, Hyper-V host name, YubiKey serial as scrub patterns (local-only, gitignored).

---

## Recent Wins (2026-06-05 to 06-15)

- ✅ **Stale-clone incident handled cleanly** (2026-06-13) — secondary Windows clone hit divergence after history rewrite; merge aborted before any compromised state was pushed; forensic verification via Events API + Wayback Machine + Traffic dashboard bounded the public exposure window; password rotated as defense in depth. Lessons-learned doc published.
- ✅ **`Architecture/Lessons-Learned/2026-06-13-Stale-Clone-After-History-Rewrite.md`** — portfolio-grade DevSecOps incident-response narrative. Documents the diagnosis, fix, forensic methodology, and the operational rule that prevents recurrence. Maps to NIST 800-53 SI-12 / CM-3 / IR-4 / AC-6 and CISA ZTMM Visibility pillar.
- ✅ **Repo hardening via fresh clone after rewrite** — old working tree discarded, fresh clone pulled, 3 gitignored local-only files restored from backup, `Scan-LocalRepo.ps1` verified all 10 patterns `[CLEAN]`.
- ✅ **`Architecture/Frameworks-Considered.md`** + CIS Controls v8 cross-reference in `SSP-Template.md` § 6.7 — multi-framework portability signal without parallel hardening work.
- ✅ **Card hardware received** — YubiKey 5 NFC units + Hirsch uTrust FIDO2 cards + additional smart cards from other vendors. v1.1 testing window now open.

---

## Recent Wins (2026-06-02 to 06-04)

- ✅ WO02 physical laptop end-to-end — domain join, VSC, smart card logon, Event 4768 Type 16 PKINIT captured
- ✅ WO02 Windows 11 STIG scan staged (37.00% baseline, 13 CAT I / 122 CAT II / 8 CAT III)
- ✅ Phase 8 Zero Trust shipped — 8 full scripts + 13 scaffolds + `Demo-Walkthrough-ZT.md`
- ✅ Lab lifecycle scripts: `Export-LabVMs.ps1`, `Import-LabVM.ps1`, `Get-LabVMSize.ps1`
- ✅ Sanitized `Lab-Kit/Reference/` (ONBOARDING + TROUBLESHOOTING) synced from lab export
- ✅ Subnet drift fixed across repo (10.10.10.x / 10.10.20.x)
- ✅ Git history rewritten + repo gated by `Scrub-Repo.ps1` + local `Scan-LocalRepo.ps1` with per-pattern `[CLEAN]`/`[LEAK]` block
- ✅ `v1.0` tagged and pushed to public GitHub (2026-06-03)
- ✅ Slot 6 PKI dashboard captured (2026-06-04 12:18:49) — `ALL CHECKS PASSED`; staged with audit-log evidence under `Compliance-Reports/PKI-Health/2026-06-04/`
- ✅ **Real-world deployment hardening** — `Monitor-PKIHealth.ps1` and `Set-AuthenticationPolicySilo.ps1` patched against PS 5.1 `AutomationNull.Count` crash and `Grant-ADAuthenticationPolicySiloAccess` group-object rejection (both found by running on Lab-DC01, not theoretical)
- ✅ **Lab-export sync — `Live-Servers/` + `Tools-Kit/` imported** — net-new folders from the lab kit (production-deployment readiness/GPO compliance helpers + tool downloaders); both clean of sensitive patterns, no scrubbing needed. README table entries were forward-declared; now backed by actual files.
- ✅ **Stale top-level `TROUBLESHOOTING.md` removed** — was a strict subset of `Lab-Kit/Reference/TROUBLESHOOTING.md`; README link updated to point at the canonical Reference/ copy.
- ✅ **WALKTHROUGH.md gap closed** — Step 3b (create Workstations OU + scope `scforceoption=1` GPO to it, BEFORE domain join) merged into Phase 6 from lab export. Closes the silent landmine where readers would link the smart-card GPO at domain root by default and lock out Lab-DC01. Includes built-in safety check that auto-removes accidental domain-root link.
- ✅ **v1.0 release notes published** (2026-06-04) — closes out v1.0 as a fully-shipped portfolio milestone (tag pushed + history clean + public repo + release notes on the tag).
- ✅ **HTTP CRL Distribution Point built on Lab-DC01** (2026-06-04) — DNS A record `pki.lab.local`, IIS + `.crl` MIME type, CRL files staged from CertEnroll, CRL validity extended 1 week → 6 months. Closes the LDAP-only gap; HTTP CRL now reachable for any non-domain-joined client.
- ✅ **Monitor-PKIHealth.ps1 — 5 additional bug fixes from parameterized real-world run** — CA cert filter false positives (VeriSign + Microsoft built-ins expired since 2002), OCSP null-guard under StrictMode, CRL binary corruption in PS 5.1 `Invoke-WebRequest`, NextUpdate regex drift vs current certutil output, `-CA.cert` invalid verb. All battle-tested. Bug-fix log staged at `Lab-Kit/03-DomainController/Bug-Fix-Logs/`. Lessons #15-20 captured.

---

*Build sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF templates: `Architecture/RMF-Templates/`*
*Phase 8–9B design: `Architecture/Roadmap/`*
*Laptop guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`*
*Frameworks comparison: `Architecture/Frameworks-Considered.md`*
*Lessons learned: `Architecture/Lessons-Learned/`*
