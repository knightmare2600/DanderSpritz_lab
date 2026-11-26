# danderspritz_lab — Proxmox + Ansible edition

A port of the DanderSpritz lab from **Packer + Vagrant + VirtualBox** to
**Proxmox VE + Ansible**. Same three hosts, same `windomain.local` domain, same
intentionally-vulnerable Windows 7 target — but the images are installed
straight onto Proxmox from ISO and every box is configured over WinRM by
Ansible instead of Vagrant.

> **This lab is intentionally vulnerable** (unpatched SMBv1 on the target,
> default `vagrant:vagrant` creds, firewall off). Keep it on an **isolated**
> Proxmox bridge with no route to anything you care about.

## How this maps to the old pipeline

| Old | New |
|-----|-----|
| Packer unattended install from ISO | `build.yml` → `roles/proxmox_vm` (`community.general.proxmox_kvm` + a generated answer-file ISO) |
| `Autounattend.xml` answer files | **Reused.** Rendered as templates with virtio `DriverPaths` + a static-IP first-logon command injected (`roles/proxmox_vm/templates/*.j2`, generated from `../answer_files/`) |
| Packer provisioners / Vagrant provisioners | `configure.yml` → `roles/{common_windows,domain_controller,target,danderspritz}`, which run the **existing** `../scripts/*.ps1` over WinRM |
| VirtualBox guest additions (`vm-guest-tools.bat`) | qemu-guest-agent (from the virtio-win ISO) |
| `vagrant-ssh.bat` / OpenSSH | dropped — Ansible connects over WinRM, which the answer files enable on first logon |

The `Vagrantfile`, `danderspritz_lab.json` and `vagrantfile-*.template` are not
used by this playbook.

## Prerequisites (one-time, manual — by design)

These are deliberately *not* automated: they are node-level and you only do them
once.

1. **Isolated bridge.** Create a Linux bridge on the Proxmox node for the lab
   net (default `vmbr40`, see `group_vars/all.yml`). Do **not** attach a
   physical NIC / uplink you care about.
2. **Pre-stage the ISOs** into the node's ISO storage (default `local`):
   - Windows Server 2008 R2 eval, Windows 7 Enterprise eval, Windows 10 1507
     Enterprise eval (filenames in `lab_vms` in `group_vars/all.yml` — the same
     ISOs the old `danderspritz_lab.json` referenced).
   - `virtio-win.iso` (latest stable from the Fedora virtio-win project).
3. **Proxmox API token.** Datacenter → Permissions → API Tokens. Put the secret
   in `group_vars/vault.yml` (copy `vault.yml.example`, then
   `ansible-vault encrypt group_vars/vault.yml`).
4. On the control node: `genisoimage` (for building the answer-file ISO) and the
   Ansible collections: `ansible-galaxy collection install -r requirements.yml`.

Set the real `proxmox_api_host`, `proxmox_node`, storage names and IPs in
`group_vars/all.yml`.

## Running

```bash
# everything: build the VMs, then configure them
ansible-playbook site.yml --ask-vault-pass

# just (re)build the VMs on Proxmox
ansible-playbook build.yml --ask-vault-pass

# just (re)configure already-built guests
ansible-playbook configure.yml --ask-vault-pass

# one host
ansible-playbook configure.yml --ask-vault-pass --limit target
```

Build is idempotent: a VM whose `vmid` already exists is left alone. To rebuild,
destroy it in Proxmox first.

`build.yml` runs a **preflight** first (`roles/preflight`): it checks via the
Proxmox API that each required ISO is present with the exact name (catching
case/spelling slips) and, when run on the PVE node, SHA-256s them against
`lab_vms[].iso_sha256`. Disable the hashing with `-e preflight_verify_sha256=false`.

**Build a subset** with `lab_vm_filter` (default `all`) — a comma-separated list
of `lab_vms` names, no file editing:

```bash
ansible-playbook build.yml -e lab_vm_filter=danderspritz --ask-vault-pass   # one box
ansible-playbook build.yml -e lab_vm_filter=dc,target     --ask-vault-pass   # a couple
```

An unknown name fails the run early with the list of valid names.

## Known rough edges (read before first run)

These are the parts that genuinely differ from VirtualBox and are most likely to
need a tweak for your node — none are hand-waved:

- **virtio driver drive letter.** `virtio_winpe_drives` (default `C:`–`H:`) in
  `roles/proxmox_vm/defaults/main.yml` are the letters the answer file offers the
  virtio CD at during install; whichever one it actually is gets the driver.
  If Setup still can't see the disk, boot the installer, press `Shift+F10`, check
  the CD letter, and widen the list. Alternative: use SATA for
  the disk and skip injection.
- **Post-promotion DC credentials.** After `dcpromo`, `vagrant` becomes a domain
  account; you may need `ansible_user: "windomain\\vagrant"` (see
  `inventory/host_vars/dc.yml`).
- **ISO / tool URL rot.** Several `../scripts/*.ps1` download tools from the
  internet (DanderSpritz, JRE 6u21, WinPython, FLARE packages). Those URLs were
  already fragile in the original project; this port does not fix them. The lab
  net therefore needs *outbound* internet during the build (via the gateway at
  `lab_gateway`), even though it must stay inbound-isolated.
- **Answer-file ISO upload** uses the Proxmox API multipart upload, which reads
  the ISO into memory. The answer-file ISO is tiny so this is fine; if you adapt
  it to push large media, scp into the node's ISO dir instead.

## Lab facts

- Domain: `windomain.local` — DC `192.168.40.2`, Target `192.168.40.3`,
  DanderSpritz `192.168.40.4`
- Admin (all boxes): `vagrant` / `vagrant`

The usage walkthrough (FuzzBunch project, EternalBlue, DoublePulsar, PeddleCheap)
is unchanged — see the top-level `../README.md`.
