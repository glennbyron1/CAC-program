# WatchGuard IKEv2 Mobile VPN — EAP-TLS Smart Card Configuration Guide

Document ID: ARCH-ICAM-005
Author: Glenn Byron
Framework: NIST SP 800-53 Rev. 5 IA-2, IA-2(11), SC-8, SC-28 | FIPS 140-3 | CISA ZTMM Identity Pillar

> **Prerequisites:** Complete the two-tier PKI deployment (`Architecture/Blueprint.md`) before
> starting this guide. The Offline Root CA, Enterprise Issuing CA, and at least one enrolled
> smart card certificate must exist before configuring IKEv2 EAP-TLS authentication.

---

## 1. Architecture Overview

WatchGuard Mobile VPN with IKEv2 uses EAP-TLS (Extensible Authentication Protocol —
Transport Layer Security) to authenticate VPN clients using their existing PKI-issued
certificates — the same hardware token used for Windows smart card logon.

This eliminates a second credential factor for VPN. The smart card IS the VPN
authenticator. No shared secrets, no passwords, no RADIUS OTP.

```
[Smart Card / YubiKey]
        │
        │  EAP-TLS (client certificate in hardware token)
        ▼
[WatchGuard Firebox]  ◄──── Server Certificate (issued by Enterprise Issuing CA)
        │
        │  Mutual certificate authentication (NIST IA-2)
        ▼
[Internal Network — Active Directory / AD CS / File Servers]
```

**Authentication flow:**
1. Windows IKEv2 client initiates tunnel to Firebox VPN gateway address
2. Firebox presents its **server certificate** (trust anchored to internal Root CA)
3. Client presents its **EAP-TLS credential** — the smart card certificate from the hardware token
4. Firebox validates the client certificate chain back to the internal Root CA
5. Tunnel established — client receives virtual IP from the configured pool

---

## 2. Prerequisites Checklist

Verify all items before starting Fireware configuration.

| Requirement | Where to Verify | Status |
|-------------|----------------|--------|
| Offline Root CA operational | `Architecture/Blueprint.md §2.1` | ☐ |
| Enterprise Issuing CA online and domain-joined | `Architecture/Blueprint.md §2.2` | ☐ |
| HTTP CRL endpoints reachable from Firebox WAN interface | `certutil -verify -urlfetch <CRL URL>` | ☐ |
| Root CA certificate (.crt) exported from Offline Root CA | `certutil -ca.cert RootCA.crt` | ☐ |
| Issuing CA certificate (.crt) exported | `certutil -ca.cert IssuingCA.crt` | ☐ |
| Smart card-enrolled test user certificate exists | `certmgr.msc` → Personal → Certificates | ☐ |
| Fireware OS version 12.5 or later (IKEv2 EAP-TLS support) | Firebox System Manager → Device tab | ☐ |
| VPN gateway DNS hostname resolves externally (e.g., vpn.agency.gov) | `nslookup vpn.agency.gov` | ☐ |
| VPN gateway server certificate template created in AD CS | Section 4.1 of this guide | ☐ |

---

## 3. AD CS Certificate Templates

Two certificate templates are required before configuring the Firebox: one for the
VPN gateway server and one for VPN client authentication. If users are already enrolled
with Smart Card Logon certificates, the client template may already exist.

### 3.1 VPN Gateway Server Certificate Template

The Firebox requires a TLS server certificate trusted by all VPN clients. This
certificate must chain back to the internal Root CA.

**Create the template in AD CS:**

1. Open **Certification Authority** console (`certsrv.msc`) on the Issuing CA server
2. Right-click **Certificate Templates** → **Manage**
3. Right-click the **Web Server** template → **Duplicate Template**
4. Configure the new template:

| Tab | Setting | Value |
|-----|---------|-------|
| General | Template display name | `VPN Gateway Server` |
| General | Validity period | 2 years |
| General | Renewal period | 6 weeks |
| Request Handling | Purpose | Signature and encryption |
| Cryptography | Provider category | Key Storage Provider |
| Cryptography | Algorithm name | RSA |
| Cryptography | Minimum key size | 2048 |
| Cryptography | Hash algorithm | SHA256 |
| Extensions → Application Policies | Extended Key Usage | Server Authentication (1.3.6.1.5.5.7.3.1) |
| Subject Name | Supply in the request | ✅ (admin submits CSR with correct SAN) |
| Security | Domain Admins | Enroll |

5. Click **OK** — template is saved but not yet published
6. Back in `certsrv.msc`: right-click **Certificate Templates** → **New** → **Certificate Template to Issue**
7. Select **VPN Gateway Server** → **OK**

**Request the VPN gateway certificate:**

Run on the Firebox management workstation or use Web UI CSR:

```powershell
# Generate a CSR for the Firebox VPN gateway certificate
# Replace vpn.agency.gov with your actual VPN gateway DNS name and IP

$inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=vpn.agency.gov,O=Agency Name,C=US"
KeySpec = 1
KeyLength = 2048
Exportable = FALSE
MachineKeySet = TRUE
SMIME = FALSE
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = PKCS10
KeyUsage = 0xa0
HashAlgorithm = SHA256

[EnhancedKeyUsageExtension]
OID = 1.3.6.1.5.5.7.3.1   ; Server Authentication

[Extensions]
2.5.29.17 = "{text}"       ; Subject Alternative Name
_continue_ = "dns=vpn.agency.gov&"
_continue_ = "ipaddress=203.0.113.1&"   ; Replace with your WAN IP
"@

$inf | Out-File -FilePath "C:\vpn-gateway.inf" -Encoding ASCII
certreq -new "C:\vpn-gateway.inf" "C:\vpn-gateway.csr"

# Submit to Issuing CA
certreq -submit -config "issuing-ca.lab.local\Lab-IssuingCA" "C:\vpn-gateway.csr" "C:\vpn-gateway.crt"
```

> **Note:** Export the signed certificate in Base64 (.crt) format. The Firebox accepts
> PEM-encoded certificates for import. If the CA issues a DER binary, convert with:
> `certutil -encode vpn-gateway.crt vpn-gateway-pem.crt`

### 3.2 VPN Client Authentication Template

For EAP-TLS, the client certificate must include the **Client Authentication** EKU
(`1.3.6.1.5.5.7.3.2`). The existing **Smart Card Logon** template already includes
this EKU alongside Smart Card Logon (`1.3.6.1.4.1.311.20.2.2`), so no new template
is required if users have enrolled smart cards.

Verify the enrolled certificate has the correct EKU:

```powershell
# List smart card certificates and their EKU extensions
Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.2" } |
    Select-Object Subject, Thumbprint, NotAfter,
        @{N='EKU';E={ $_.EnhancedKeyUsageList.FriendlyName -join ', ' }}
```

If a dedicated VPN client template is needed (without Smart Card Logon EKU):

1. Duplicate the **User** template
2. Name it `VPN Client Authentication`
3. Extensions → Application Policies: add **Client Authentication** only
4. Subject Name: **Build from Active Directory information** (uses UPN for matching)
5. Security: Domain Users — Autoenroll

---

## 4. WatchGuard Fireware Configuration

All steps below use the **Fireware Web UI** (`https://<firebox-IP>:8080`). Policy
Manager (Windows GUI) follows the same logical path.

### 4.1 Import the CA Certificate Chain

The Firebox must trust the internal Root CA and Issuing CA to validate client certificates.

1. Log in to **Fireware Web UI** as admin
2. Navigate to **System** → **Certificates**
3. Click **Import Certificate**
4. **Certificate Type:** Select `Certificate Authority (CA)`
5. Paste or upload the **Root CA certificate** (Base64 PEM format)
6. Click **Save** — the Root CA appears in the certificate list
7. Repeat steps 3–6 for the **Issuing CA certificate**

Verify both certificates appear under the **CA Certificates** section with green status.

> **Important:** The CRL Distribution Points in both CA certificates must be reachable
> from the Firebox WAN interface. If the Firebox cannot download a CRL during
> authentication, the VPN tunnel will fail. Test from the Firebox diagnostic tools:
> **System** → **Diagnostic Tasks** → **TCP Connection** → test TCP 80 to your CRL server.

### 4.2 Import the VPN Gateway Server Certificate

1. **System** → **Certificates** → **Import Certificate**
2. **Certificate Type:** Select `Certificate (PEM format with key)`
3. Upload or paste the VPN gateway certificate (`vpn-gateway-pem.crt`)
4. Upload or paste the private key (if the CSR was generated externally)
5. Click **Save**
6. Verify the certificate appears with:
   - Subject: `CN=vpn.agency.gov` (matching your gateway DNS)
   - Issuer: your Enterprise Issuing CA name
   - Valid: green status, expiry date shown

### 4.3 Configure Mobile VPN with IKEv2

1. Navigate to **VPN** → **Mobile VPN** → **IKEv2** tab
2. Click **Activate** (if IKEv2 is not enabled)
3. Configure the following settings:

**General Settings**

| Setting | Value | Notes |
|---------|-------|-------|
| Server Certificate | `vpn.agency.gov` | The certificate imported in §4.2 |
| Authentication Method | `EAP-TLS` | Certificate-based — no password |
| EAP-TLS CA Certificate | Select your Root CA + Issuing CA | Used to validate client certs |
| Virtual IP Address Pool | `10.100.200.0/24` | Addresses assigned to VPN clients |
| DNS Server | `10.0.0.10` (DC IP) | Internal DNS for name resolution |
| DNS Suffix | `lab.local` | Resolves internal hostnames over tunnel |
| WINS Server | (leave blank unless legacy required) | |

> **EAP-TLS vs EAP-MSCHAPv2:** EAP-TLS provides phishing-resistant, certificate-based
> mutual authentication (NIST IA-2). EAP-MSCHAPv2 uses passwords and is explicitly
> prohibited in a zero-password topology. Select EAP-TLS only.

### 4.4 IKE Phase 1 (IKE SA) Cryptographic Settings

Phase 1 establishes the secure channel used to negotiate the VPN tunnel parameters.

Navigate to **VPN** → **Mobile VPN** → **IKEv2** → **Phase 1 Settings** tab.

| Setting | Required Value | Rationale |
|---------|---------------|-----------|
| Encryption | AES-256-GCM | NIST SP 800-57 approved; authenticated encryption |
| Authentication | SHA-256 (or SHA-384) | FIPS 180-4 approved hash |
| Diffie-Hellman Group | Group 20 (ECP-384) or Group 14 (MODP-2048) | NSA CNSSP-15 minimum; Group 20 preferred |
| SA Lifetime | 86400 seconds (24 hours) | Limits key material exposure |
| Dead Peer Detection | Enabled | Cleans up stale tunnels |
| DPD Delay | 30 seconds | |
| DPD Timeout | 150 seconds | |

> **Avoid:** DES, 3DES, MD5, SHA-1, DH Groups 1/2/5. These are deprecated and
> prohibited under FIPS 140-3. Fireware ≥ 12.5 offers AES-256-GCM — select it
> over plain AES-256-CBC for authenticated encryption (eliminates separate HMAC).

### 4.5 IPSec Phase 2 (Child SA) Cryptographic Settings

Phase 2 defines the encryption applied to actual VPN data traffic.

Navigate to **VPN** → **Mobile VPN** → **IKEv2** → **Phase 2 Settings** tab.

| Setting | Required Value | Rationale |
|---------|---------------|-----------|
| Encryption | AES-256-GCM | Authenticated encryption (no separate Auth needed) |
| Authentication | SHA-256 | Required if using AES-CBC; GCM mode is self-authenticating |
| PFS (Perfect Forward Secrecy) | Group 14 or Group 20 | Ensures session key compromise does not expose past sessions |
| SA Lifetime (Time) | 28800 seconds (8 hours) | |
| SA Lifetime (Traffic) | 4608000 KB | Rekeying based on traffic volume |

### 4.6 VPN Client Resources

Define what internal resources VPN clients can reach after authentication.

1. **VPN** → **Mobile VPN** → **IKEv2** → **Resources** tab
2. Add the internal networks VPN clients need access to:

| Network | Purpose |
|---------|---------|
| `10.0.0.0/8` | Internal corporate network (adjust to your addressing) |
| `192.168.0.0/16` | Local LAN segments |
| DNS server IP (e.g., `10.0.0.10/32`) | Must be routed over tunnel for internal DNS |

> **Split Tunnel vs Full Tunnel:** For a zero-trust posture, configure **force tunneling**
> (full tunnel) so all client internet traffic is inspected by the Firebox. In Fireware,
> add `0.0.0.0/0` to the resource list to route all traffic through the tunnel.
> Split tunnel reduces bandwidth load but reduces visibility into endpoint behavior.

### 4.7 Firewall Policies for VPN Traffic

IKEv2 requires specific ports open on the WAN interface.

**Required inbound policy on WAN interface:**

| Protocol | Port | Purpose |
|----------|------|---------|
| UDP | 500 | IKE key exchange (Phase 1) |
| UDP | 4500 | IKE NAT Traversal (ESP encapsulated in UDP) |
| ESP | Protocol 50 | IPSec data packets (if not NATted) |

In Fireware Policy Manager or Web UI:
1. **Firewall** → **Firewall Policies** → **Add Policy**
2. Name: `IKEv2-Mobile-VPN-Inbound`
3. From: `Any-External`
4. To: `Firebox`
5. Ports: UDP 500, UDP 4500
6. Action: Allow
7. Enable logging for audit compliance

**Policy for VPN client access to internal resources:**

1. Name: `VPN-Clients-Internal-Access`
2. From: `SSLVPN` alias (Fireware auto-creates this for Mobile VPN clients) or the virtual IP pool
3. To: `Any-Trusted` or specific internal resource aliases
4. Action: Allow
5. Enable: Application Control, IPS if licensed

---

## 5. Windows Client Deployment

Deploy the IKEv2 VPN client profile to endpoints via PowerShell or Group Policy.
See `Automation-Scripts/Deploy-VPNClient.ps1` for the automated deployment script.

### 5.1 Manual Client Configuration (Single Endpoint)

```powershell
# Step 1 — Add the IKEv2 VPN connection
Add-VpnConnection `
    -Name "Agency VPN" `
    -ServerAddress "vpn.agency.gov" `
    -TunnelType IKEv2 `
    -AuthenticationMethod MachineCertificate `
    -EncryptionLevel Maximum `
    -SplitTunneling $false `
    -RememberCredential $false `
    -PassThru

# Step 2 — Set FIPS-compliant IPSec crypto policy (must match Firebox Phase 1/2 config)
Set-VpnConnectionIPsecConfiguration `
    -ConnectionName "Agency VPN" `
    -AuthenticationTransformConstants GCMAES256 `
    -CipherTransformConstants GCMAES256 `
    -EncryptionMethod AES256 `
    -IntegrityCheckMethod SHA256 `
    -DHGroup ECP384 `
    -PfsGroup ECP384 `
    -PassThru

# Step 3 — Configure EAP-TLS to use smart card certificate (machine or user cert)
# See Deploy-VPNClient.ps1 for EAP XML profile configuration
```

### 5.2 Group Policy Deployment

For domain-wide VPN profile deployment:

1. Open **Group Policy Management** (`gpmc.msc`) on a domain controller
2. Create a new GPO: `SEC-VPN-IKEv2-Profile`
3. Navigate to:
   **Computer Configuration** → **Windows Settings** → **Security Settings**
   → **Network List Manager Policies** (for network name)
4. For VPN connection, use GPO **Preferences**:
   **Computer Configuration** → **Preferences** → **Control Panel Settings**
   → **Network Options** → **New** → **VPN Connection**
5. Alternatively, deploy the VPN profile via PowerShell startup script
   (see `Automation-Scripts/Deploy-VPNClient.ps1`)

### 5.3 EAP-TLS XML Profile (Smart Card Authentication)

Windows IKEv2 requires an EAP XML configuration to specify certificate selection
criteria. This ensures the correct smart card certificate is used — not any available
certificate in the store.

```xml
<!-- EAP-TLS profile: forces smart card certificate selection -->
<!-- Deploy via rasphone.pbk or PowerShell EAP profile parameter -->
<EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
  <EapMethod>
    <Type xmlns="http://www.microsoft.com/provisioning/EapCommon">13</Type>
    <VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorId>
    <VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon">0</VendorType>
    <AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon">0</AuthorId>
  </EapMethod>
  <Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig">
    <Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1">
      <Type>13</Type>
      <EapType xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV1">
        <CredentialsSource>
          <!-- SmartCard: forces hardware token — no software cert fallback -->
          <SmartCard/>
        </CredentialsSource>
        <ServerValidation>
          <!-- Validate Firebox server certificate against internal CA -->
          <DisableUserPromptForServerValidation>true</DisableUserPromptForServerValidation>
          <ServerNames>vpn.agency.gov</ServerNames>
          <!-- Trusted Root CA Thumbprint — replace with your Root CA thumbprint -->
          <TrustedRootCA>00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF 00 11 22 33</TrustedRootCA>
        </ServerValidation>
        <DifferentUsername>false</DifferentUsername>
        <PerformServerValidation xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV2">true</PerformServerValidation>
        <AcceptServerName xmlns="http://www.microsoft.com/provisioning/EapTlsConnectionPropertiesV2">true</AcceptServerName>
      </EapType>
    </Eap>
  </Config>
</EapHostConfig>
```

> **Replace** `00 11 22 33 ...` with your actual Root CA thumbprint:
> `(Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*RootCA*" }).Thumbprint`

---

## 6. CRL Accessibility Verification

The Firebox validates client certificates against the CRL at time of connection.
If the CRL endpoint is unreachable, authentication fails. Verify before go-live.

```powershell
# Run on the Firebox management workstation OR use Firebox diagnostic tools

# Test HTTP CRL endpoint reachability
$crlUrl = "http://crl.agency.gov/crl/IssuingCA.crl"
try {
    $response = Invoke-WebRequest -Uri $crlUrl -Method Head -UseBasicParsing -TimeoutSec 10
    Write-Host "CRL endpoint reachable: HTTP $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "CRL endpoint UNREACHABLE: $_" -ForegroundColor Red
    Write-Host "VPN authentication will fail if CRL is cached and expired." -ForegroundColor Yellow
}

# Verify the CRL itself is valid and not expired
certutil -verify -urlfetch "C:\Path\To\IssuingCA.crl"

# Check CRL next update field
$crl = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
# (use certutil -dump IssuingCA.crl to read NextUpdate field)
certutil -dump "C:\Path\To\IssuingCA.crl" | Select-String "NextUpdate"
```

---

## 7. Testing and Validation

### 7.1 End-to-End Connection Test

```powershell
# On a test endpoint with an enrolled smart card:

# 1. Verify the smart card certificate is present and valid
Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.2" } |
    Select-Object Subject, Thumbprint, NotAfter

# 2. Initiate VPN connection (will prompt for smart card PIN if card is present)
rasdial "Agency VPN"

# 3. Verify tunnel is up and virtual IP assigned
Get-VpnConnection -Name "Agency VPN" | Select-Object ConnectionStatus, ServerAddress
ipconfig | Select-String "10.100.200"   # Virtual IP pool range

# 4. Test internal resource access over tunnel
Test-NetConnection -ComputerName "dc01.lab.local" -Port 389   # LDAP to DC
Test-NetConnection -ComputerName "10.0.0.10" -Port 445         # SMB to file server
Resolve-DnsName "dc01.lab.local"                                # Internal DNS

# 5. Disconnect
rasdial "Agency VPN" /disconnect
```

### 7.2 Audit Log Verification

After a successful connection, verify the correct event IDs are logged:

| Event ID | Source | Meaning |
|----------|--------|---------|
| 20225 | RasClient | IKEv2 connection established |
| 20226 | RasClient | IKEv2 connection terminated |
| 4769 | Security | Kerberos service ticket request (smart card) |
| 4624 | Security | Logon — Type 3 (Network) with certificate |

In Fireware, check: **System** → **Traffic Monitor** → filter for the client IP.

### 7.3 Certificate Revocation Test

Verify the Firebox enforces revocation:

```powershell
# On the Issuing CA server — revoke the test user's certificate
certutil -revoke <SerialNumber> 3   # Reason: Key Compromise
certutil -CRL                       # Publish updated CRL immediately

# Attempt VPN connection from the test endpoint (should fail with cert error)
rasdial "Agency VPN"
# Expected: Error 13806 — IKE failed to find valid machine certificate
# or: Error 691 — Authentication failed (certificate revoked)
```

This confirms the Firebox is actively checking the CRL on each authentication attempt.

---

## 8. Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Error 13806 — No machine cert | Client cert missing Client Auth EKU | Verify cert EKU includes `1.3.6.1.5.5.7.3.2`; re-enroll if needed |
| Error 13801 — IKE auth failed | CA chain not trusted on Firebox | Re-import Root CA + Issuing CA certs in Firebox System → Certificates |
| Error 809 — No response from server | UDP 500/4500 blocked | Check WAN firewall policy; verify IKEv2 policy exists on Firebox |
| Error 691 — Auth failed | CRL check failed (endpoint unreachable) | Verify CRL URL is reachable from Firebox WAN; check HTTP 80 policy |
| Error 691 — Auth failed | Certificate revoked | Check client cert status: `certutil -verify -urlfetch <cert>` |
| Tunnel up, no internal access | Missing VPN resource policy | Add internal subnets to IKEv2 Resources; add Firewall policy from VPN pool |
| Frequent disconnects | Phase 2 lifetime mismatch | Match SA lifetime values exactly between Firebox and Windows client |
| Smart card PIN not prompted | EAP profile using cert store, not card | Apply EAP XML with `<SmartCard/>` CredentialsSource (see §5.3) |
| Cannot resolve internal DNS | DNS not routed over tunnel | Add DNS server IP to VPN Resources list; verify DNS Suffix configured |

### Firebox Diagnostic Commands (SSH or WatchGuard System Manager)

```bash
# Show active IKEv2 SAs
show ikev2 sa

# Show active IPSec tunnels
show ipsec sa

# Debug IKEv2 negotiation (verbose — run during connection attempt)
debug ikev2 all

# Show certificate store
show certificate ca
show certificate device

# Test CRL download from Firebox
ping host http://crl.agency.gov
```

---

## 9. NIST SP 800-53 Rev. 5 Control Mapping

| Control ID | Control Name | WatchGuard IKEv2 Implementation |
|-----------|-------------|--------------------------------|
| IA-2 | Identification and Authentication | EAP-TLS authenticates users via PKI certificate — hardware-backed, phishing-resistant |
| IA-2(11) | Remote Access — Separate Device | Smart card hardware token required; certificate non-exportable from token |
| IA-3 | Device Identification and Authentication | Machine certificates (optional second factor) authenticate the endpoint itself |
| SC-8 | Transmission Confidentiality and Integrity | AES-256-GCM encrypts and authenticates all VPN data in transit |
| SC-8(1) | Cryptographic Protection | FIPS 140-3 approved algorithms: AES-256-GCM, SHA-256, DH Group 14/20 |
| SC-28 | Protection of Information at Rest | Key material resides in smart card hardware — never exported to OS key store |
| AC-17 | Remote Access | IKEv2 VPN is the mandated remote access method; no password-based alternatives permitted |
| AC-17(2) | Protection of Remote Access Using Encryption | AES-256-GCM + IKEv2 enforces encryption for all remote sessions |
| SC-17 | Public Key Infrastructure Certificates | VPN gateway certificate and client certificates both issued by internal two-tier PKI |
| AU-2 | Event Logging | Firebox Traffic Monitor + Windows Event IDs 20225/20226 log all VPN sessions |
| SI-7(6) | Cryptographic Protection of Software | Code signing verification on Fireware updates via WatchGuard signature validation |

---

## 10. Signing Ceremony Integration

The VPN gateway server certificate (2-year validity) must be renewed before expiry.
The Issuing CA handles this — no Offline Root CA signing ceremony required unless
the Issuing CA certificate itself is being renewed.

**Certificate renewal schedule:**

| Certificate | Validity | Renewal Trigger | Action |
|-------------|---------|----------------|--------|
| VPN Gateway Server cert | 2 years | 6 weeks before expiry | Request new cert from Issuing CA; import to Firebox |
| Issuing CA certificate | 5 years | 6 months before expiry | Power on Offline Root CA; signing ceremony |
| Root CA certificate | 10 years | 2 years before expiry | Signing ceremony; new Root CA cert published to AD |
| User Smart Card cert | 1–2 years | Auto-renew via autoenrollment GPO | AD CS handles automatically |

Set a calendar reminder for the VPN gateway cert renewal — Fireware does NOT
automatically alert on certificate expiry. A lapsed server certificate causes all
VPN connections to fail enterprise-wide.

```powershell
# Check VPN gateway certificate expiry on Windows
$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like "*vpn.agency.gov*" }
$daysLeft = ($cert.NotAfter - (Get-Date)).Days
Write-Host "VPN Gateway cert expires: $($cert.NotAfter) ($daysLeft days remaining)"
if ($daysLeft -lt 42) { Write-Warning "Renewal required — less than 6 weeks remaining" }
```

---

*This guide is part of the CAC/PIV Program documentation set.
For PKI architecture, see `Architecture/Blueprint.md`.
For client deployment automation, see `Automation-Scripts/Deploy-VPNClient.ps1`.
For regulatory framework alignment, see `Architecture/Regulatory-Alignment.md`.*
