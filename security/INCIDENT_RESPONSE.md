# Incident Response — Sensitive Data Committed

**Author:** Glenn Byron

If a secret, certificate, key, VM image, or real organizational identifier is
committed to this repository, treat it as a compromise. Removing the file in a
new commit is **not** sufficient — Git history retains every prior version, and
if it was pushed, it may already be cloned or cached.

## Trigger Conditions

- A private key, certificate, or CSR was committed
- A CA database (`CertLog/`, `*.edb`) or VM image was committed
- Credentials, a password, or PowerShell history were committed
- Real domains, public IPs, hostnames, or employee names were committed

## Immediate Actions (in order)

1. **Stop pushing.** Do not add more commits on top until contained.
2. **Identify the exposed data** and every commit that contains it:
   ```bash
   git log --all --full-history -- <path/to/file>
   ```
3. **If a credential or key was exposed, rotate it now** — assume it is burned:
   - Revoke the certificate at the CA and publish a fresh CRL:
     ```text
     certutil -revoke <SerialNumber>
     certutil -crl
     ```
   - Disable or reissue any affected account or key. A leaked private key is
     compromised the moment it is pushed; revocation is mandatory, not optional.

## Containment — Purge From History

Deleting the file is not enough. Rewrite history to remove it everywhere:

```bash
# Preferred: git-filter-repo (install separately)
git filter-repo --path <path/to/secret> --invert-paths

# Fallback: BFG Repo-Cleaner
# bfg --delete-files <filename>
```

Then force-push the rewritten history and tell any collaborators to re-clone:
```bash
git push --force --all
git push --force --tags
```

> If the repository is public and the secret was pushed, assume it was
> harvested by automated scrapers within minutes. Rotation (step 3) is the real
> remediation; history rewriting just prevents re-exposure.

## Recovery

- Issue new credentials / certificates to replace anything revoked.
- Update any system that trusted the revoked material.
- Confirm CI (`secret-scan.yml`) passes on the cleaned repository.

## Cleanup and Review

- Verify the secret is gone from all branches and tags.
- Confirm `.gitignore`, the pre-commit hook, and CI would have caught it; if
  not, add the missing pattern so it cannot recur.
- Note the incident and the fix in your commit message.

## Reporting

If this repository is tied to an organization, notify your IT/security lead.
For vulnerabilities in the repository's code or tooling (as opposed to an
accidental commit), use the disclosure process in the root
[`SECURITY.md`](../SECURITY.md).
