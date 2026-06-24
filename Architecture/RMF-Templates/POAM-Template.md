# Plan of Action & Milestones (POA&M)

Document ID: ARCH-ICAM-007
Author: Glenn Byron
Framework: NIST SP 800-53 Rev. 5 CA-5 | NIST SP 800-37 Rev. 2 | DISA RMF

> **How to use this template:** Add a row for every open finding from your SCAP SCC STIG scans
> and Nessus Essentials results. Update the Status column as findings are remediated. The AO
> reviews this document before granting an ATO — every open Critical finding must either be
> remediated or have a documented risk acceptance before authorization is granted.
>
> Risk Levels follow DISA CAT designations: CAT I = Critical, CAT II = High, CAT III = Medium/Low.

---

## System Information

| Field | Value |
|-------|-------|
| System Name | Enterprise CAC/PIV ICAM System |
| Document ID | ARCH-ICAM-007 |
| Prepared By | Glenn Byron |
| Date Prepared | June 1, 2026 |
| Last Updated | June 17, 2026 (STIG CAT I review populated + IIS STIG assessment) |
| Assessment Period | May – June 2026 |

---

## POA&M Summary Dashboard

Update this table after each remediation cycle.

Sources:
- SCAP SCC 5.10.2 · MS_Windows_Server_2022_STIG-2.3.10 · DC01 + WS01 · scanned 2026-05-28
- SCAP SCC 5.10.2 · Microsoft_Windows_11_STIG-2.3.9 · WO02 · scanned 2026-06-02
- SCAP SCC 5.10.2 · IIS_10-0_Server_STIG-3.2.9 + IIS_10-0_Site_STIG-2.10.10 · LAB-DC01 (CRL/AIA HTTP endpoint) · scanned 2026-06-24

| Risk Level | Total Findings (all hosts + IIS) | Remediated | Accepted Risk | Open |
|-----------|---------------|------------|---------------|------|
| CAT I (Critical) | 24 unique rules (OS: 22 across 3 hosts + IIS: 2 on DC01) | 0 | 2 pending (BitLocker WO02) + 1 pending (HTTPS-required IIS SV-218821 — RFC 5280 risk-accept) | 21 (after risk-accepts applied) |
| CAT II (High) | 366 total (OS: 343 + IIS: 23 across Server + Site) | 0 | ~6 pending Risk Accept (SSL/HTTPS-related IIS findings — N/A on HTTP CRL endpoint per RFC 5280) | ~360 |
| CAT III (Medium/Low) | 22 total (OS: 20 + IIS: 2) | 0 | 1 pending (HSTS — depends on HTTPS) | ~19 |
| **NotChecked (SCAP Manual Questions)** | 29 IIS rules pending STIG Viewer manual answer | — | — | 29 |
| **Total open** | **~408** | **0** | **~10 pending** | **~400** |

> **STIG reviews complete (2026-06-17 OS / 2026-06-24 IIS):** all CAT I rules across the OS STIGs (DC01 / WS01 / WO02) AND the IIS STIGs (Server + Site on LAB-DC01) are populated below with dispositions. Smart-card-related STIG rules **passed** — identity authentication controls IA-2 / IA-2(11) / AC-5 are satisfied. The **headline IIS finding (SV-218821 — HTTPS required)** is **Risk Accept** with RFC 5280 §4.2.1.13 rationale: HTTP-only CRL distribution is the standard federal pattern (DoD CRL endpoints also use HTTP) because TLS would create circular validation (TLS cert needs CRL which is served over TLS which needs CRL...).

---

## Open Findings

One row per finding. Copy and add rows as needed. Findings come from three sources:
- **SCC** — SCAP SCC automated STIG scan (XCCDF results in `Compliance-Reports/`)
- **STIG-V** — Manual review in DISA STIG Viewer (.ckl checklist)
- **Nessus** — Nessus Essentials credentialed vulnerability scan

### CAT I — Critical Findings

> **22 unique CAT I findings across 3 hosts**, populated 2026-06-17 from STIG Viewer .ckl review and XCCDF parse. Smart-card-related STIG rules (`WN22-SO-000120` interactive logon require smart card; `WN22-CC-000080` smart card removal behavior) **PASSED** the scans and are not in this open-findings list — they were correctly applied via `Build-CA-GPO.ps1`. The 22 open CAT I items below are general Windows hardening gaps grouped into 7 categories.

**Disposition summary (all 22 CAT I — none are false positives; all are real findings):**

| Disposition | Count | Notes |
|---|---|---|
| Open — Ansible remediation queued | 18 | Will close via `Lab-Kit/Ansible/windows-stig-hardening.yml` |
| Open — manual review required | 1 | AD data files permissions (DC-specific) |
| Open — risk-accept candidate | 2 | BitLocker disk encryption + BitLocker PIN (lab usability tradeoff) |
| Open — operational no-op, remediate anyway | 4 | WinRM Basic auth (lab uses Kerberos PSRemoting; disabling Basic has no operational impact) |
| Cleared — STIG passed | (smart-card rules above) | `WN22-SO-000120`, `WN22-CC-000080`, etc. — verified passing on all hosts |

---

#### Group 1 — AutoPlay / AutoRun (6 findings)

Common to all platforms. Real findings; registry/GPO-deliverable; remediable via Ansible playbook.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-001 | SV-254352 | Windows Server 2022 Autoplay must be turned off for nonvolume devices | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`HKLM\...\NoAutoplayfornonVolume` = 1) |
| POA-002 | SV-254353 | Windows Server 2022 default AutoRun behavior must be configured to prevent AutoRun commands | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`NoAutorun` = 1) |
| POA-003 | SV-254354 | Windows Server 2022 AutoPlay must be disabled for all drives | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`NoDriveTypeAutoRun` = 0xFF) |
| POA-004 | SV-253386 | Windows 11 Autoplay must be turned off for non-volume devices | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-001) |
| POA-005 | SV-253387 | Windows 11 default autorun behavior must be configured to prevent autorun commands | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-002) |
| POA-006 | SV-253388 | Windows 11 Autoplay must be disabled for all drives | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-003) |

#### Group 2 — Windows Installer "Always install with elevated privileges" (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-007 | SV-254374 | Windows Server 2022 Windows Installer "Always install with elevated privileges" must be disabled | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`AlwaysInstallElevated` = 0). Privilege-escalation vector if enabled. |
| POA-008 | SV-253411 | Windows 11 "Always install with elevated privileges" must be disabled | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-007) |

#### Group 3 — WinRM Basic Authentication (4 findings — operational no-op)

The lab uses **Kerberos** for PowerShell Remoting (proven during the v1.2 build session: `Invoke-Command -ComputerName Lab-DC01` worked with domain credentials; PowerShell Direct over the hypervisor channel also worked). Disabling Basic auth has **no operational impact** but should still be remediated for hardening completeness.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-009 | SV-254378 | Windows Server 2022 WinRM client must not use Basic authentication | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`AllowBasic` = 0). No operational impact — lab uses Kerberos. |
| POA-010 | SV-254381 | Windows Server 2022 WinRM service must not use Basic authentication | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Same as POA-009 (service-side counterpart) |
| POA-011 | SV-253416 | Windows 11 WinRM client must not use Basic authentication | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-009 |
| POA-012 | SV-253418 | Windows 11 WinRM service must not use Basic authentication | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-010 |

#### Group 4 — Anonymous Enumeration of Shares (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-013 | SV-254467 | Windows Server 2022 must not allow anonymous enumeration of shares | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`RestrictNullSessAccess` = 1) |
| POA-014 | SV-253454 | Windows 11 anonymous enumeration of shares must be restricted | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-013 |

#### Group 5 — LAN Manager Authentication Level (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-015 | SV-254475 | Windows Server 2022 LAN Manager authentication level must be configured to send NTLMv2 response only / refuse LM and NTLM | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`LmCompatibilityLevel` = 5). Modern Windows is NTLMv2-by-default but STIG checks explicit policy. |
| POA-016 | SV-253462 | Windows 11 LanMan authentication level must be set to send NTLMv2 response only, and to refuse LM and NTLM | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-015 |

#### Group 6 — AD Data Files Permissions (1 finding — DC-specific manual review)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-017 | SV-254391 | Windows Server 2022 permissions on the Active Directory data files must only allow System and Administrators access | SCC | LAB-DC01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | **Manual review required**: verify ACLs on `%SYSTEMROOT%\NTDS\*` directly on Lab-DC01. Not safely automatable; over-tight permissions can break AD replication. Will validate during the Ansible STIG hardening pass and document the ACLs in the SAR. |

#### Group 7 — Windows 11 Specific (5 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-018 | SV-253259 | Windows 11 information systems must use BitLocker to encrypt all disks | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open — risk-accept candidate | WO02 has TPM 2.0 so BitLocker is feasible. **Risk-accept rationale (lab):** no production data on WO02; physical access controlled (residential office). Compensating controls: smart-card-required logon + 2-second `ScRemoveOption` lock + Hyper-V host BitLocker (where lab VMs live). Moving to Risk Acceptance Register pending decision. |
| POA-019 | SV-253260 | Windows 11 systems must use a BitLocker PIN for pre-boot authentication | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open — risk-accept candidate | TPM-only vs TPM+PIN tradeoff. Common federal risk-accept with documented operational rationale. Pending Risk Acceptance Register entry. |
| POA-020 | SV-253283 | Windows 11 Data Execution Prevention (DEP) must be configured to at least OptOut | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`bcdedit /set nx OptOut`). |
| POA-021 | SV-253284 | Windows 11 Structured Exception Handling Overwrite Protection (SEHOP) must be enabled | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`DisableExceptionChainValidation` = 0). |
| POA-022 | SV-253382 | Windows 11 Solicited Remote Assistance must not be allowed | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`fAllowToGetHelp` = 0). |

#### Group 8 — IIS 10.0 Server STIG CAT I (2 findings on LAB-DC01 CRL endpoint)

LAB-DC01 hosts the **HTTP CRL Distribution Point** (`http://pki.lab.local/crl/`) — static-file IIS serving CRL files from `C:\Windows\System32\CertSrv\CertEnroll\`. No app server features installed; no scripting; anonymous read only. Scanned 2026-06-24 against `IIS_10-0_Server_STIG-3.2.9` MAC-2 Sensitive profile.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-023 | SV-218795 | All IIS 10.0 web server sample code, example applications, and tutorials must be removed from a production server | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open — verify | Likely already N/A — no app server features installed (no ASP.NET, no PHP, no sample apps). Action: manual check `Get-ChildItem C:\inetpub\` and `C:\Program Files\IIS Express\` for any sample subdirectories; remove if present. |
| POA-024 | SV-218821 | An IIS 10.0 web server must maintain the confidentiality of controlled information during transmission | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **Risk Accept** ⭐ | **Headline finding.** HTTP-only CRL distribution is **RFC 5280 §4.2.1.13** permitted; the standard federal pattern (DoD CRL endpoints also HTTP) because HTTPS would create circular validation (TLS cert needs CRL which is served over TLS which needs CRL...). The CRL files themselves are signed by the Issuing CA; integrity is end-to-end via the CRL signature, not transport. Moving to Risk Acceptance Register as RA-003. |

#### Group 9 — IIS 10.0 Site STIG CAT I (0 findings — none flagged on the CRL site)

Site STIG returned **zero CAT I FAIL** for the Default Web Site on LAB-DC01 (1 CAT I notchecked — pending STIG Viewer manual review). The Site STIG's CAT II findings (15) are populated below; many are SSL/TLS-dependent and trigger N/A or Risk Accept under the same RFC 5280 rationale as POA-024.

### CAT II — High Findings

#### OS STIGs (Server 2022 + Windows 11) — bulk row

> DC01: 110 open · WS01: 111 open · WO02: 122 open. Full list in STIG Viewer from .ckl files.
> Bulk remediation via `Lab-Kit/Ansible/windows-stig-hardening.yml`.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-025 | [See XCCDF XML] | 343 CAT II findings — see STIG Viewer | SCC | LAB-DC01 / LAB-WS01 / WO02 | 2026-05-28 / 2026-06-02 | Q3 2026 | Glenn Byron | Open | Bulk remediation planned via Ansible STIG hardening playbook |

#### IIS Server STIG CAT II (8 findings — itemized)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-026 | SV-218786 | Both log file and ETW for IIS 10.0 web server must be enabled | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Enable W3C log + ETW provider via `appcmd set config /section:httpLogging`. Standard audit configuration. |
| POA-027 | SV-218788 | IIS 10.0 web server must produce log records that contain sufficient information to establish what type of events occurred | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | W3C log field configuration — add `s-sitename`, `s-computername`, `s-ip`, `cs-method`, `cs-uri-stem`, `cs-uri-query`, `s-port`, `cs-username`, `c-ip`, `cs(User-Agent)`, `sc-status`, `time-taken`. |
| POA-028 | SV-218789 | IIS 10.0 web server must produce log records containing sufficient information to establish where events occurred | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Companion to POA-027 — additional log fields. |
| POA-029 | SV-218798 | IIS 10.0 web server must have MIME types that invoke OS shells disabled | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Remove MIME mappings for `.exe`, `.dll`, `.com`, `.bat`, `.csh` from IIS staticContent. Critical hardening — privilege escalation vector. |
| POA-030 | SV-218807 | Production IIS 10.0 web server must utilize SHA2 encryption for the Machine Key | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Set machineKey decryption to AES, validation to SHA512. `aspnet_regiis -pi` or `web.config` machineKey section. |
| POA-031 | SV-218819 | IIS 10.0 web server must be tuned to handle the operational requirements of the hosted application | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Tune `system.webServer/serverRuntime` per the hosted-application traffic profile. For static CRL files: small worker process count, low queue length appropriate. |
| POA-032 | SV-218825 | IIS 10.0 web server must have a global authorization rule configured to restrict access | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Add `<authorization><deny users="?" /></authorization>` to root applicationHost.config and override for `/crl/` virtual directory to allow anonymous (CRL distribution requires anonymous read by design). |
| POA-033 | SV-268325 | The Request Smuggling filter must be enabled | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Enable via `appcmd set config /section:system.webServer/security/requestFiltering -enableHttpRequestSmugglingFilter:true`. Standard HTTP-smuggling defense. |

#### IIS Site STIG CAT II (15 findings — itemized with N/A dispositions)

A meaningful subset of the Site STIG CAT II findings are **N/A or Risk Accept** for this specific deployment because the CRL distribution endpoint is **deliberately HTTP-only per RFC 5280 §4.2.1.13** and serves **no application logic** (no cookies, no client auth, no session state). Findings related to SSL/HTTPS, client certificates, and cookie security inherit the same Risk Accept rationale as POA-024 (the headline CAT I finding).

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-034 | SV-218737 | A private IIS 10.0 website must only accept SSL connections | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **Risk Accept** | This is a **public CRL distribution endpoint**, not a private website. Inherits RFC 5280 risk-accept rationale (see POA-024). Moving to Risk Acceptance Register as RA-004. |
| POA-035 | SV-218738 | A public IIS 10.0 website must only accept SSL connections when authenticating users | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **N/A** | The CRL endpoint has no authentication mechanism — anonymous read only. SSL-when-authenticating is moot when there is no authentication. Disposition: N/A. |
| POA-036 | SV-218739 | Both log file and ETW for each IIS 10.0 website must be enabled | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Site-level companion to POA-026. Same remediation pattern. |
| POA-037 | SV-218741 | IIS 10.0 website must produce log records that contain sufficient information to establish what type of events occurred | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Site-level companion to POA-027. |
| POA-038 | SV-218742 | IIS 10.0 website must produce log records containing sufficient information to establish where events occurred | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Site-level companion to POA-028. |
| POA-039 | SV-218743 | IIS 10.0 website must have MIME types that invoke OS shells disabled | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Site-level companion to POA-029. |
| POA-040 | SV-218748 | Each IIS 10.0 website must be assigned a default host header | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Set the Default Web Site binding to `*:80:pki.lab.local` instead of `*:80:` (no host header). Prevents host-header injection. |
| POA-041 | SV-218749 | A private IIS 10.0 website authentication mechanism must use client certificates | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **N/A** | Public CRL endpoint — no client cert auth by design. Same rationale as POA-024 / POA-034. |
| POA-042 | SV-218752 | IIS 10.0 website document directory must be in a separate partition from the IIS 10.0 website application | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open — review | The CRL files live at `C:\Windows\System32\CertSrv\CertEnroll\`. Strict interpretation says move to a separate partition. Practical disposition: documented architecture decision — CRL content management is tightly coupled to AD CS which manages the source location. |
| POA-043 | SV-218756 | Non-ASCII characters in URLs must be prohibited by any IIS 10.0 website | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Enable via `<requestFiltering allowHighBitCharacters="false" />`. Standard input filtering. |
| POA-044 | SV-218758 | Unlisted file extensions in URL requests must be filtered by any IIS 10.0 website | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Allow-list filter: only `.crl`, `.crt`, `.cer` extensions. Set via `<requestFiltering><fileExtensions allowUnlisted="false">` + explicit allowed extensions. |
| POA-045 | SV-218763 | IIS 10.0 websites connectionTimeout setting must be explicitly configured | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Set `<sessionState timeout="00:20:00" />` or `<httpRuntime executionTimeout="..." />` per IIS-10 STIG default (5 min recommended for static content). |
| POA-046 | SV-218768 | IIS 10.0 private website must employ TLS and require client certificates | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **N/A** | Same disposition as POA-041. Public CRL endpoint by design. |
| POA-047 | SV-218770 | Cookies exchanged between IIS 10.0 website and client must have cookie properties set to indicate validation | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **N/A** | Static CRL endpoint sets no cookies. The rule has no operational footprint. |
| POA-048 | SV-218772 | Maximum number of requests an application pool can process for each IIS 10.0 website must be set | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q3 2026 | Glenn Byron | Open | Set application pool recycling: `recycling.periodicRestart.requests` to e.g. `100000`. Prevents memory drift. |

### CAT III — Medium / Low Findings

#### OS STIGs — bulk row

> DC01: 6 · WS01: 6 · WO02: 8. Low priority; address after CAT I/II remediation.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-049 | [See XCCDF XML] | 20 CAT III findings — see STIG Viewer | SCC | LAB-DC01 / LAB-WS01 / WO02 | 2026-05-28 / 2026-06-02 | Q4 2026 | Glenn Byron | Open | Low priority; address after CAT I/II remediation |

#### IIS STIG CAT III (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-050 | SV-218827 | IIS 10.0 web server must enable HTTP Strict Transport Security (HSTS) | SCC | LAB-DC01 (IIS) | 2026-06-24 | N/A | Glenn Byron | **Risk Accept** | HSTS requires HTTPS first. Since POA-024 risk-accepts HTTP-only for CRL distribution, HSTS has no surface to enable. Moving to Risk Acceptance Register as RA-005 (dependent finding). |
| POA-051 | SV-241788 | HTTPAPI Server version must be removed from the HTTP Response Header information | SCC | LAB-DC01 (IIS) | 2026-06-24 | Q4 2026 | Glenn Byron | Open | Minor information-disclosure hardening. Remove via registry: `HKLM\SYSTEM\CurrentControlSet\Services\HTTP\Parameters` set `DisableServerHeader` to 2. |

---

## Closed / Remediated Findings

Move findings here once remediation is confirmed by a follow-up SCAP SCC scan or STIG Viewer re-check.

| ID | STIG / Plugin ID | Finding Title | Risk Level | Remediation Action | Closure Date | Verified By |
|----|-----------------|---------------|------------|-------------------|--------------|-------------|
| | | | | | | |

---

## Risk Acceptance Register

Use this section for findings that cannot be remediated within the authorization period and where
residual risk is formally accepted by the system owner or AO.

| ID | Finding Title | Risk Level | Reason Cannot Remediate | Compensating Controls | Risk Accepted By | Acceptance Date | Expiration |
|----|--------------|------------|------------------------|----------------------|-----------------|-----------------|------------|
| RA-001 | BitLocker disk encryption on WO02 (SV-253259) | CAT I | Lab environment with no production data; BitLocker key escrow process for federal deployment requires AD recovery key infrastructure not in scope for this lab tier | Smart-card-required interactive logon (scforceoption=1); 2-second session lock on card removal (ScRemoveOption=1); physical access controlled (residential office); Hyper-V host where lab VMs live runs BitLocker | Glenn Byron (System Owner / Self-Assessed Lab AO) | [Pending decision] | Annual review 2027-05 |
| RA-002 | BitLocker pre-boot PIN on WO02 (SV-253260) | CAT I | TPM-only vs TPM+PIN is a documented federal risk-accept pattern; TPM-only provides tamper-evidence; pre-boot PIN is operational-burden tradeoff for kiosk/shared-workstation scenarios | TPM 2.0 provides tamper-evidence; Smart-card-required logon at OS boundary; physical access control | Glenn Byron | [Pending decision] | Annual review 2027-05 |
| RA-003 | HTTPS-required on IIS CRL endpoint (SV-218821) | CAT I | **Standard federal pattern.** HTTP-only CRL distribution is permitted by RFC 5280 §4.2.1.13. DoD CRL endpoints (e.g., DoD Root CA-3 CRL) are served over HTTP. HTTPS would create circular validation: TLS cert validity depends on CRL freshness, but CRL is served over TLS which requires CRL validation, etc. The CRL files themselves are signed by the Issuing CA — integrity is end-to-end via cryptographic signature, NOT transport. | (1) CRL files cryptographically signed by Issuing CA (integrity end-to-end); (2) CRL distribution is public information by design (no confidentiality requirement); (3) HTTP/IP layer isolation per Architecture/Lab-Topology.md SC-7 boundary controls; (4) Endpoint exists only inside the lab segment behind air-gap (production deployment would expose only the static CRL files via reverse proxy with no admin interface) | Glenn Byron | 2026-06-24 | Annual review 2027-06 |
| RA-004 | Site STIG SSL requirement on IIS CRL endpoint (SV-218737) | CAT II | Inherits the same rationale as RA-003. The "private website must accept SSL only" rule applies to private/internal websites, NOT to public CRL distribution endpoints which are public by design. | Same as RA-003 | Glenn Byron | 2026-06-24 | Annual review 2027-06 |
| RA-005 | HSTS dependent on HTTPS (SV-218827) | CAT III | HSTS (HTTP Strict Transport Security) is a header that instructs browsers to upgrade to HTTPS. It has no operational footprint when HTTPS is not enabled in the first place. Dependent on RA-003 disposition. | Inherits RA-003 controls; HSTS adds nothing when HTTPS is intentionally not deployed | Glenn Byron | 2026-06-24 | Annual review 2027-06 |

---

## Remediation Notes

### Common STIG Findings for This Environment

The following are findings commonly flagged in Windows Server 2022 and AD DS STIG scans that this
program's hardening scripts address. Check off as confirmed remediated by your post-hardening scan.

| STIG Rule ID | Finding | Remediated By | Confirmed |
|-------------|---------|---------------|-----------|
| WN22-CC-000080 | Smart card removal policy must be configured | `Build-CA-GPO.ps1` — ScRemoveOption = 1 | [ ] |
| WN22-SO-000120 | Interactive logon: require smart card | `Group-Policy/Enforce-SmartCard.ps1` — scforceoption = 1 | [ ] |
| WN22-AU-000050 | Audit logon events must be enabled | `Build-CAC-Lab.ps1` audit policy configuration | [ ] |
| WN22-CC-000210 | WDigest Authentication must be disabled | GPO — registry: `UseLogonCredential = 0` | [ ] |
| [Add others from your scan results] | | | |

---

## Milestone Schedule

| Milestone | Target Date | Owner | Status |
|-----------|-------------|-------|--------|
| Before-MFA SCAP SCC scans complete | 2026-05-27 | Glenn Byron | [x] |
| After-MFA SCAP SCC scans complete | 2026-05-28 | Glenn Byron | [x] |
| Initial POA&M populated from scan results | 2026-06-01 | Glenn Byron | [x] |
| Nessus Essentials credentialed scan | Q3 2026 | Glenn Byron | [ ] |
| STIG Viewer manual CAT I review complete (OS STIGs) | 2026-06-17 | Glenn Byron | [x] |
| IIS STIG assessment complete (Server STIG 3.2.9 + Site STIG 2.10.10 on LAB-DC01) | 2026-06-24 | Glenn Byron | [x] |
| STIG Viewer manual review of 29 IIS notchecked rules (SCAP Manual Questions) | Q3 2026 | Glenn Byron | [ ] |
| Ansible STIG hardening playbook run (CAT I/II remediation) | Q3 2026 | Glenn Byron | [ ] |
| Post-remediation SCAP scan to verify improvements | Q3 2026 | Glenn Byron | [ ] |
| CAT I findings remediated or risk accepted | Q3 2026 | Glenn Byron | [ ] |
| SSP finalized | Q3 2026 | Glenn Byron | [ ] |
| ATO decision | Q4 2026 | TBD (AO) | [ ] |
| First annual re-assessment | May 2027 | Glenn Byron | [ ] |

---

## Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | May 2026 | Glenn Byron | Initial template created |
| 1.0 | June 1, 2026 | Glenn Byron | Populated with Before/After-MFA SCAP SCC scan results |
| 1.1 | June 17, 2026 | Glenn Byron | STIG Viewer CAT I review: all 22 unique CAT I findings across DC01 / WS01 / WO02 populated with disposition and remediation plan. Confirmed smart-card-related STIG rules (`WN22-SO-000120`, `WN22-CC-000080`) passed the scans (identity controls IA-2 / AC-5 / IA-2(11) fully satisfied). Risk Acceptance Register seeded with two pending entries (RA-001 BitLocker disk encryption, RA-002 BitLocker pre-boot PIN). Dashboard updated with WO02 Win11 STIG numbers. |
| 1.2 | June 24, 2026 | Glenn Byron | IIS STIG assessment complete: scanned LAB-DC01 IIS 10.0 CRL/AIA endpoint against IIS Server STIG 3.2.9 (53.85% score) and Site STIG 2.10.10 (54.55% score). 2 CAT I findings populated (POA-023 sample code removal — Open; POA-024 HTTPS-required — **Risk Accept** ⭐ headline finding with RFC 5280 §4.2.1.13 rationale). 23 CAT II findings populated and itemized — Server STIG 8 + Site STIG 15 (subset N/A due to RFC 5280 public-CRL-endpoint architecture). 2 CAT III findings (HSTS dependent on HTTPS — Risk Accept; HTTPAPI server header — Open). Risk Acceptance Register extended: RA-003 (HTTPS-required CAT I), RA-004 (SSL Site CAT II), RA-005 (HSTS CAT III). Closes the "STIG Viewer CAT I review" + "IIS STIG assessment" items from POA&M Still Needs Input section. |

---

*Related documents: `SSP-Template.md`, `SAR-Template.md`,
`Compliance-Reports/README.md`. See [`TODO.md`](../../TODO.md) (Phase 5 — RMF Authorize) for the full ATO package checklist.*
