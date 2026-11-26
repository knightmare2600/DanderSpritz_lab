# Bringing up the DanderSpritz lab on Proxmox VE

A hands-on, start-to-finish runbook for standing the lab up on a Proxmox VE node
using the Ansible playbook in [`danderspritz_lab/`](danderspritz_lab/). It
assumes you are sitting at a booted PVE node with the three Windows ISOs to
hand. For the background on *how* the port works and the full checksum table,
see the "Building on Proxmox VE with Ansible" section of the top-level
[`README.md`](README.md) and [`danderspritz_lab/README.md`](danderspritz_lab/README.md).

Ansible runs **from the PVE host itself** here — it is the simplest control node,
as it can reach both the Proxmox API and the lab bridge.

> This lab is **intentionally vulnerable** (unpatched SMBv1 target, default
> `vagrant:vagrant` creds, firewall off). Keep `vmbr40` off anything you care
> about. "Isolated" means no *inbound* from real networks — it still needs
> *outbound* internet during the build for the tool downloads.

---

## TL;DR of the ordering

bridge + NAT → verify + stage ISOs → API token → ansible + collections →
edit `all.yml` + vault → `build.yml` one box (eyeball virtio) → `site.yml` →
exploit test.

---

## 1. Network: isolated bridge with a NAT gateway

On the node, add to `/etc/network/interfaces` (swap `vmbr0` for your WAN-facing
bridge):

```
auto vmbr40
iface vmbr40 inet static
    address 192.168.40.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   iptables -t nat -A POSTROUTING -s 192.168.40.0/24 -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s 192.168.40.0/24 -o vmbr0 -j MASQUERADE
```

```bash
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf && sysctl -p
ifreload -a
```

## 2. Stage the ISOs (verified) into PVE storage

Drop the three Windows ISOs plus the latest stable `virtio-win.iso` into the
node's ISO storage (`/var/lib/vz/template/iso/` for the `local` storage, or via
the GUI). **Verify them first** against the known checksums:

```bash
# DC — Windows Server 2008 R2 SP1
md5sum  7601.17514.101119-1850_x64fre_server_eval_en-us-GRMSXEVAL_EN_DVD.iso
#   == 4263be2cf3c59177c45085c0a7bc6ca5

# Target — Windows 7 Enterprise RTM
md5sum  7600.16385.090713-1255_x64fre_enterprise_en-us_EVAL_Eval_Enterprise-GRMCENXEVAL_EN_DVD.iso
#   == 1d0d239a252cb53e466d39e752b17c28

# DanderSpritz — Windows 10 1507 Enterprise Eval
sha1sum 10240.16384.150709-1700.TH1_CLIENTENTERPRISEEVAL_OEMRET_X64FRE_EN-US.ISO
#   == 56ab095075be28a90bc0b510835280975c6bb2ce
```

A single matching hash is enough to trust the file; the full MD5/SHA-1/SHA-256
set for all three ISOs is in the top-level [`README.md`](README.md) if you want
to check more than one.

You do not have to do this check entirely by hand: `build.yml` runs a
**preflight** before creating anything. It asks the Proxmox API whether each
required ISO is present under the exact name (catching a missing file or an
upper/lower-case slip and telling you which variant it found), and — when
Ansible is running on the PVE node — SHA-256s each one against the pinned value.
A wrong name or hash stops the run immediately instead of part-way through a
long build. The hashing reads multi-GB files, so skip it for a fast run with
`-e preflight_verify_sha256=false`.

## 3. API token

GUI → Datacenter → Permissions → API Tokens → add `root@pam`, token id
`ansible`, and **untick Privilege Separation** (so it inherits root's rights —
fine for a lab). Copy the secret; it is shown once.

## 4. Control node setup (on the PVE host)

```bash
apt install -y ansible genisoimage curl git
git clone https://github.com/knightmare2600/DanderSpritz_lab.git
cd DanderSpritz_lab
git checkout danderspritz_lab-proxmox        # until PR #1 is merged to master
cd danderspritz_lab
ansible-galaxy collection install -r requirements.yml
```

## 5. Point it at your node

Edit `group_vars/all.yml` — `proxmox_api_host`, `proxmox_node`, the storage
names, `proxmox_lab_bridge: vmbr40`, and `proxmox_virtio_iso`. The ISO filenames
already match what you staged. Then the secret:

```bash
cp group_vars/vault.yml.example group_vars/vault.yml
vim group_vars/vault.yml                      # paste the real token secret
ansible-vault encrypt group_vars/vault.yml
```

## 6. Prove it on ONE box first

Build just the Win10 box — it has no domain dependency and exercises the two
parts most likely to need a tweak (virtio driver injection + WinRM):

```bash
ansible-playbook build.yml -e lab_vm_filter=danderspritz --ask-vault-pass
```

Open that VM's console in the PVE GUI and **watch the install**. The make-or-break
check: if Windows Setup reports it cannot find a disk, the virtio driver letter
is wrong — press `Shift+F10`, run `diskpart` → `list volume` to find the virtio
CD's letter, set `virtio_winpe_drive` in `roles/proxmox_vm/defaults/main.yml`,
and retry. When it is up:

```bash
ansible danderspritz -m ansible.windows.win_ping --ask-vault-pass
ansible-playbook configure.yml --limit danderspritz --ask-vault-pass
```

## 7. Build the whole lab

```bash
ansible-playbook site.yml --ask-vault-pass
```

This builds all three VMs, then configures them in order: common prep →
**DC promoted** → target joins the domain → DSZ box. Expect long waits on the DC
`dcpromo` (~15–30 min) and the Win7 SP1 install (~40 min); the playbook waits
them out.

If WinRM to the DC fails right after promotion (the local `vagrant` account
becomes a domain account at that point), set
`ansible_user: "windomain\\vagrant"` in `inventory/host_vars/dc.yml` and re-run
`ansible-playbook configure.yml --limit dc --ask-vault-pass`.

## 8. Prove the lab actually works

On the DSZ box, run the FuzzBunch → EternalBlue → DoublePulsar → PeddleCheap
walkthrough in the top-level [`README.md`](README.md). That is the real
acceptance test — a green Ansible run alone does not prove the exploit path.

---

## Known rough edges

- **virtio drive letter** (step 6) — the one assumption that cannot be verified
  without a running node. Alternative: use a SATA disk and skip driver injection.
- **Tool-download URL rot** — several of the old `scripts/*.ps1` fetch tools
  (DanderSpritz, JRE 6u21, WinPython, FLARE packages) from the internet. Those
  URLs were already fragile in the original project and some may have rotted;
  this is why the lab bridge needs outbound internet during the build. The
  direct-download files worth vendoring into the repo are listed in
  [`danderspritz_lab/offline-assets.md`](danderspritz_lab/offline-assets.md).

## Day-to-day

```bash
# rebuild one box (destroy it in Proxmox first - build skips existing vmids)
ansible-playbook build.yml -e lab_vm_filter=target --ask-vault-pass
ansible-playbook configure.yml --limit target --ask-vault-pass

# re-run configuration on a host
ansible-playbook configure.yml --limit danderspritz --ask-vault-pass
```
