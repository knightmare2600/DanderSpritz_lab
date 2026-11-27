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

## How vendored files are delivered — the tools CD

Vendored installers live in the repo's top-level **`tools/`** directory. At build
time, `roles/proxmox_vm` builds a small ISO from the files mapped in
`danderspritz_tools` (`group_vars/all.yml`), uploads it to Proxmox storage, and
attaches it as a CD (ide3) to any VM with `tools_iso: true` (currently the
DanderSpritz box). During configuration the guest copies them off that CD to
where each `Install-*.ps1` expects them; the scripts now use the local copy if
present and **fall back to downloading** if not — so the lab builds both offline
and online. This avoids dragging the files over WinRM (slow) and is how larger
additions (e.g. SP1) would be delivered too. The preflight SHA-256s everything
in `tools/` against the mapping before a build starts.

> virtio drivers and the qemu guest agent are **not** vendored here — they come
> from the `virtio-win.iso` attached at build time (drivers in the windowsPE
> pass, agent installed by `common_windows`). No need to add them to `tools/`.

## DanderSpritz box (Windows 10) — ✅ vendored & wired

In `tools/`, delivered via the tools CD, SHA-256 pinned in `danderspritz_tools`:

| Filename | What it is | Original source | Risk if not vendored |
|----------|-----------|----------------|------|
| `jre-6u21-windows-i586.exe` | Java 6u21 — the DanderSpritz/FuzzBunch GUI needs **Java 6** specifically | `ww2.chemistry.gatech.edu/software/JRE/...` (a university mirror) | **HIGH** |
| `pywin32-221.win32-py2.6.exe` | pywin32 build 221 for **32-bit** Python 2.6 (must be `win32`, not `win-amd64`) | SourceForge (`jaist.dl.sourceforge.net`) | **HIGH** |
| `python-2.6.6.msi` | Python 2.6.6 (32-bit) | `github.com/numpy/numpy-vendor/raw/master/...` | MEDIUM |

Downloaded at build time and baked onto the tools CD (not in the repo — ~200 MB):

| Item | What it is | Source | Handling |
|------|-----------|--------|----------|
| `EQGRP_Lost_in_Translation` | **DanderSpritz + FuzzBunch themselves** — extracted to `C:\Users\vagrant\eqtools` | `codeload.github.com/x0rz/EQGRP_Lost_in_Translation/zip/refs/heads/master` (`eqgrp_url`) | `build.yml` downloads it once on the control node (cached in `eqgrp_cache_dir`), adds the zip to the tools CD, and the guest expands it — no git/internet needed on the guest. `Install-DanderSpritz.ps1` falls back to `git clone` if the zip isn't staged. The upstream repo has been dormant ~9 years, so the master archive is effectively a fixed snapshot — pinning a commit in `eqgrp_url` is optional. Set `fetch_eqgrp: false` to skip and clone on the guest instead. |

## Target box (Windows 7) — SP1 on the tools CD

| Filename | What it is | Source | Decision |
|----------|-----------|--------|----------|
| `windows6.1-KB976932-X64.exe` | Windows 7 **SP1** (~903 MB / 947,070,088 bytes; saved on the guest as `KB976932-X64.exe`; SHA-256 `f4d1d418…aa64c8`) | A dedicated **Internet Archive item** (`sp1_url`) whose archive-computed MD5+size match the published installer — **Microsoft removed the original** (do not use a Wayback `id_` capture; those truncate large files) | **Fetched onto the target's tools CD** (`fetch_sp1: true`): a copy vendored in `tools/` is preferred, else `build.yml` downloads it (SHA-256-verified via `sp1_sha256`). On an already-built target with no CD, the target role downloads it on the guest instead (also SHA-256-verified). Override `sp1_url` with a LAN HTTP URL to serve a vendored copy from the control node and avoid the pull over the lab NAT. `Install-SP1.ps1` only runs the staged, verified file. |

## PowerShell 5.1 bootstrap — cold 2008 R2 (DC) and Win7 (target)

These boxes ship **PowerShell 2.0**; modern `ansible.windows` modules require
**5.1**, and a cold PS 2.0 box can't TLS-download installers. So both are
vendored in `tools/` and installed **at first logon** from each box's tools CD
(answer-file orders 25–27), before Ansible connects. Both are gitignored (large).

| Filename | What it is | Source | Decision |
|----------|-----------|--------|----------|
| `NDP452-KB2901907-x86-x64-AllOS-ENU.exe` | .NET Framework **4.5.2** (~69 MB; SHA-256 `6c2c5891…a86f3781`) — WMF 5.1 prerequisite | Microsoft Download Center (id=42642) / web archive | Vendored on the DC+target CD; installed `/q /norestart` at first logon. SHA-256 verified by preflight. |
| `Win7AndW2K8R2-KB3191566-x64.msu` | **WMF 5.1 / PowerShell 5.1** (~80 MB) — extract from `...-x64.zip` | Microsoft Download Center (id=54616) / Legacy Update | Vendored on the DC+target CD; installed `wusa /quiet /norestart`, then a reboot activates PS 5.1. Set `sha256` in `windows_bootstrap_tools` to enforce verification. |

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
  `scripts/Target/Set-ChocolateyFLARERepo.ps1`) was the source for the Target's
  reversing tools: `apimonitor`, `exeinfope`, `hxd`, `peid`, `peview`, `windbg`,
  `wireshark.flare`, `binaryninja`, `hashcalc`, `idafree70`, `ollydbg2`.
  **Status: effectively dead for this lab (verified Nov 2025).** The feed's index
  URL still responds, but an OData `FindPackagesById` query for every one of
  those IDs returns an *empty* feed — none are served any more. Separately,
  current FLARE-VM has moved to `myget.org/F/vm-packages` and now **requires
  Windows ≥ 10 / PowerShell ≥ 5 / Chocolatey ≥ 2**, so repointing the Win7
  target at the new feed is not a fix (those packages won't install on Win7).

  **How the playbook handles it:** these installs are now **optional and
  non-fatal** (`roles/target`, gated by `target_install_flare`, default `true`).
  They are split out of the essential tooling, so a dead feed no longer aborts
  the Target build or the domain join — the tools are simply skipped with a
  warning. Set `target_install_flare: false` to skip them outright. The lab's
  exploit chain does not use them. Reinstating them would mean individually
  sourcing Win7-compatible builds and vendoring them onto the tools CD — a
  separate project, not a feed URL swap.

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
