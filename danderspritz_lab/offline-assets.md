# Offline assets — files to vendor into the repo

The build pulls a number of things off the internet. Most go through Chocolatey
(a package *feed*, not a single file — see the bottom of this page), but a
handful are **direct downloads of specific files** from third-party mirrors that
rot. Those are the ones worth committing to the repo so the lab builds without
depending on a URL staying alive.

> **Not verified from here:** I have not been able to test which of these URLs
> are still live (the build host that produced this note has no outbound
> access). Risk levels below are judgement from the source, not confirmed
> reachability. Treat "HIGH" as "assume it's gone, vendor it".

Drop the files into **`danderspritz_lab/files/offline/`** (create it) keeping the
exact filenames below. Once they're in, tell me and I will wire the playbook /
scripts to install from the local copy instead of the URL (the scripts currently
hard-code the URLs, so vendoring alone does not change behaviour yet).

## DanderSpritz box (Windows 10) — the important ones

| Filename | What it is | Current source | Risk |
|----------|-----------|----------------|------|
| `jre-6u21-windows-i586.exe` | Java 6u21 — the DanderSpritz/FuzzBunch GUI needs **Java 6** specifically | `ww2.chemistry.gatech.edu/software/JRE/...` (a university mirror) | **HIGH** |
| `pywin32-221.win32-py2.6.exe` | pywin32 build 221 for Python 2.6 | SourceForge (`jaist.dl.sourceforge.net`) | **HIGH** |
| `python-2.6.6.msi` | Python 2.6.6 (32-bit) | `github.com/numpy/numpy-vendor/raw/master/...` | MEDIUM |
| `EQGRP_Lost_in_Translation` (whole repo) | **DanderSpritz + FuzzBunch themselves** — `git clone`d to `C:\Users\vagrant\eqtools` | `github.com/x0rz/EQGRP_Lost_in_Translation.git` | MEDIUM — this is the crown jewel; vendor it as a zip or git submodule so a takedown can't kill the lab |

## Target box (Windows 7)

| Filename | What it is | Current source | Risk |
|----------|-----------|----------------|------|
| `windows6.1-KB976932-X64.exe` | Windows 7 **SP1** (~903 MB; the script saves it as `KB976932-X64.exe`) | `download.microsoft.com/download/0/A/F/...` | LOW–MEDIUM (Microsoft-hosted, but large and worth caching) |

## Domain controller (Server 2008 R2)

| Filename | What it is | Current source | Risk |
|----------|-----------|----------------|------|
| `windows-event-forwarding-master.zip` | Palantir WEF subscriptions/configs | `github.com/palantir/windows-event-forwarding/archive/master.zip` | MEDIUM |

## Not single files — feeds (flagged, can't just "drop in a file")

- **Chocolatey** (`chocolatey.org/install.ps1` + the community feed) provides:
  `git.install`, `powershell`, `dotnet4.5`, the Win7 KB packages
  (`KB2454826`, `KB2534366`, `KB2533552`, `KB3035131`, `KB3033929`, `KB2999226`),
  `vcredist2015`, `sysinternals`, `sysmon`. These generally still resolve.
  Risk: LOW–MEDIUM.
- **FLARE myget feed** (`myget.org/F/flare`, added by
  `scripts/Target/Set-ChocolateyFLARERepo.ps1`) provides the reversing tools:
  `windbg`, `peid`, `exeinfope`, `peview`, `ollydbg2`, `apimonitor`, `hxd`,
  `wireshark`, `binaryninja`, `hashcalc`, `ida` (free). **Risk: HIGH** — FLARE-VM
  moved its package source off this myget feed years ago, so it is very likely
  defunct. If so, these installs fail and the Target comes up without the RE
  tools (the lab still exploits fine; it just lacks the analysis kit). Fixing
  this properly means either pointing at the current FLARE-VM package source or
  vendoring each tool — a bigger job than the single-file list above, so worth a
  separate decision.

---

## Required ISOs (full filenames, for reference)

| Host | Full ISO filename |
|------|-------------------|
| DC (Server 2008 R2 SP1, x64) | `7601.17514.101119-1850_x64fre_server_eval_en-us-GRMSXEVAL_EN_DVD.iso` |
| Target (Windows 7 Enterprise RTM, x64) | `7600.16385.090713-1255_x64fre_enterprise_en-us_EVAL_Eval_Enterprise-GRMCENXEVAL_EN_DVD.iso` |
| DanderSpritz (Windows 10 1507 Enterprise Eval, x64) | `10240.16384.150709-1700.TH1_CLIENTENTERPRISEEVAL_OEMRET_X64FRE_EN-US.ISO` |

These are **not** vendored into the repo (licensing + size); stage them into
Proxmox ISO storage as described in [`../proxmox.md`](../proxmox.md). Checksums
are in the top-level [`../README.md`](../README.md).
