# Maintainer Setup Guide

This file is a one-time setup checklist for the repository maintainer
(currently Glenn Byron). It is not user-facing documentation and is
intentionally kept short. Treat it as a per-machine checklist that you
work through once on each machine where you'll be committing to this repo.

## 1. Use a GitHub-Provided Noreply Email for Git Commits

GitHub provides a `users.noreply.github.com` address for every account. Use
that as your git commit email so your real personal email is never exposed
in this repository's history.

### Get your noreply address

1. Browser: GitHub → Settings → Emails.
2. Tick **Keep my email addresses private**.
3. Copy the address shown in the "Your primary email address" hint — it
   has the format `12345678+glennbyron1@users.noreply.github.com`.

### Configure git to use it (per-repository)

From inside the repository folder:

```powershell
git config user.name  "Glenn Byron"
git config user.email "12345678+glennbyron1@users.noreply.github.com"
```

Use `--global` if you'd like the same identity everywhere. The per-repository
form (no `--global`) is the safest — it applies only to this repo, so any
other git work you do is unaffected.

### Verify

```powershell
git config user.name
git config user.email
```

The email should be the noreply address, not your personal address.

## 2. Sign Commits with SSH (Recommended)

Signed commits show a green **Verified** badge next to each commit on
github.com. For a security-focused portfolio this is a meaningful signal —
it's the cryptographic proof that the commit actually came from you.

GitHub supports SSH signing directly with your existing SSH key — no GPG
setup required.

### One-time SSH key creation

If you don't already have an SSH key:

```powershell
ssh-keygen -t ed25519 -C "12345678+glennbyron1@users.noreply.github.com"
# Press Enter to accept the default path. Set a passphrase.
```

### Tell git to sign with that SSH key

```powershell
git config gpg.format ssh
git config user.signingkey "$HOME\.ssh\id_ed25519.pub"
git config commit.gpgsign true
```

(`--global` works here too if you want signing everywhere.)

### Register the signing key on GitHub

1. Browser: GitHub → Settings → SSH and GPG keys.
2. Add a **new SSH key**, set the type to **Signing Key** (not
   Authentication Key), and paste the contents of
   `~/.ssh/id_ed25519.pub`.

### Verify on the next commit

After your next commit and push, the commit shows a **Verified** badge in
the GitHub web UI. If it doesn't, double-check that the public key
registered in GitHub matches the one referenced by `user.signingkey`.

## 3. Initialize the Local Scrub Patterns File

The scrubber loads real identifiers from a gitignored file. Create it
once per machine:

```powershell
Copy-Item .scrub-patterns.example.json .scrub-patterns.local.json
notepad .scrub-patterns.local.json
```

Edit the file with your real organizational identifiers. The `.local.json`
file is gitignored and will never be pushed.

## 4. Pre-Push Routine (Every Time)

Before pushing changes to GitHub:

```powershell
.\Scrub-Repo.ps1 -WhatIf      # preview replacements
.\Scrub-Repo.ps1               # apply
git diff                       # review
git add .
git commit -m "Your message"
git push
```

## 5. Pin the Repository on Your GitHub Profile

For maximum portfolio visibility:

1. Browser: GitHub profile (https://github.com/glennbyron1) → click
   **Customize your pins**.
2. Select `CAC-program` (and any other portfolio repos you want
   featured).
3. Save.

The repo now appears in the pinned section at the top of your profile —
the first thing recruiters see.
