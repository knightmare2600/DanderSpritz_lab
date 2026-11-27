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

## 1. Network

Three modes, set by `lab_network_mode` in `group_vars/all.yml`. **Pick one.**
Whichever you choose, the guests need **outbound** internet during the build
(SP1, Chocolatey, FLARE), so something has to route/NAT the lab subnet.

### `managed` (default) — the playbook makes an isolated bridge, the host NATs

Leave `lab_network_mode: managed` and do *not* make the bridge by hand. On build,
`roles/proxmox_net` checks the API: if `proxmox_lab_bridge` (e.g. `vmbr40`) is
free it creates an isolated bridge (no uplink, gateway IP, comment
`danderspritz-lab`); if the name is already taken it stops and asks for a
different `vmbrN`, re-checking until you give a free one. The API **cannot** add
the outbound NAT, so after it runs add the masquerade rule on the node:

```
# /etc/network/interfaces — swap vmbr0 for your WAN-facing bridge
auto vmbr40
iface vmbr40 inet static
    address 192.168.40.1/24
    post-up   iptables -t nat -A POSTROUTING -s 192.168.40.0/24 -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s 192.168.40.0/24 -o vmbr0 -j MASQUERADE
```
```bash
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf && sysctl -p && ifreload -a
```

### `existing` — attach to a bridge you already have, you do the routing

Set `lab_network_mode: existing` and `proxmox_lab_bridge` to your bridge. The
playbook touches no host networking; your existing setup routes/NATs the lab
subnet. `lab_gateway` must be whatever gateway lives on that network.

### `routed` — the playbook builds a NAT gateway for you

Set `lab_network_mode: routed`. The playbook stands up a tiny Debian **LXC** that
*is* `192.168.40.1`: WAN leg on `lab_gateway_wan_bridge` (default `vmbr0`, via
DHCP), LAN leg on the isolated lab bridge, running `dnsmasq` (DHCP
`lab_dhcp_range_start`–`end`, default `.100`–`.150`, + DNS) and `nftables`
masquerade. Isolated **and** internet-connected, with **no host NAT** and nothing
for you to hand-build.

In this mode the lab hosts get their documented addresses by **DHCP reservation**
(each VM has a fixed `mac` in `lab_vms`; the gateway's dnsmasq maps MAC → `.2/.3/.4`,
outside the pool) rather than the answer file's native static IP, which is skipped —
far more reliable than configuring static IPs inside Windows at first boot. Extra
hosts dropped on the lab net get a `.100–150` lease.

This is the only mode that needs **root SSH from the control node to the PVE
node** — `gateway.yml` runs there (`pct`/`pveam`/`pvesh`) to create the bridge,
auto-download the LXC template, and build + configure the container. `site.yml`
runs `gateway.yml` before `build.yml` automatically; standalone, run it first:

```bash
ansible-playbook gateway.yml -e lab_network_mode=routed \
  -e proxmox_api_host=<node-ip> -e proxmox_node=<node-name>
# override lab_gateway_rootfs_storage if local-lvm isn't your storage (e.g. local-zfs)
```

### `tagged` — bring your own firewall VM on a VLAN

Set `lab_network_mode: tagged`, `proxmox_lab_bridge` to your existing bridge
(e.g. `vmbr0`), and `lab_vlan` to a VLAN id (e.g. `40`). Every lab VM's NIC is
then an access port on that VLAN (`virtio,bridge=vmbr0,tag=40`). You run your
**own firewall VM** — pfSense, OPNsense, IPFire, etc. — with a leg on the same
bridge+VLAN, and *it* is the lab's gateway/NAT/DHCP. The playbook creates no
bridge and does no host NAT.

With this model:
- Give the firewall VM's LAN interface the address you set as `lab_gateway`
  (default `192.168.40.1`); the lab guests already point their gateway there.
- The firewall VM's WAN leg goes on a bridge with an uplink; its LAN leg on the
  tagged VLAN. It provides the outbound path, so no host NAT is needed.
- **Isolation caveat:** a VLAN tag only isolates the lab if VLAN `lab_vlan` is
  not trunked out of the node to somewhere it shouldn't go. On a single node with
  a VLAN-aware bridge that's automatic; if `vmbr0` has a physical uplink, make
  sure your switch doesn't carry that VLAN anywhere you care about. The firewall
  VM's WAN should be the lab's only way out.

> DHCP vs static: the answer files set **static** IPs (`192.168.40.2/3/4`), so
> the guests come up reachable regardless of whether your firewall VM also runs
> DHCP. Just make sure its LAN IP is `lab_gateway` and it isn't handing out those
> three addresses to anything else.

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

## 3. Proxmox credentials

Two auth methods, set by `proxmox_auth_method` in `group_vars/all.yml`:

- **`token`** (default, recommended): GUI → Datacenter → Permissions → API
  Tokens → add `root@pam`, token id `ansible`, and **untick Privilege
  Separation** (so it inherits root's rights — fine for a lab). Copy the secret;
  it is shown once. Set `proxmox_api_user: root@pam` and
  `proxmox_api_token_id: ansible`.
- **`password`**: just a PVE login — set `proxmox_api_user` to the account
  (realm included, e.g. `root@pam`). No token needed; the playbook logs in for a
  ticket itself.

Either way the **secret** (token secret or password) is supplied at run time —
see step 5. Nothing secret goes in `group_vars/all.yml`.

## 4. Control node setup (on the PVE host)

```bash
apt install -y ansible genisoimage curl git
git clone https://github.com/knightmare2600/DanderSpritz_lab.git
cd DanderSpritz_lab/danderspritz_lab
ansible-galaxy collection install -r requirements.yml
```

## 5. Point it at your node, and the secret

Edit `group_vars/all.yml` — `proxmox_auth_method`, `proxmox_api_host`,
`proxmox_node`, the storage names, `proxmox_lab_bridge`, and `proxmox_virtio_iso`.
The ISO filenames already match what you staged.

The secret is **not** stored in `all.yml`. Provide it whichever way suits:

- **Prompt (simplest):** run `build.yml`/`site.yml` and type it at the hidden
  prompt (`Proxmox secret — …`). Nothing to set up.
- **Unattended:** pass it on the command line, e.g.
  `-e proxmox_secret_prompt='xxxx'` (press-Enter is skipped).
- **Vault:** store it encrypted and press Enter at the prompt to fall back to it:
  ```bash
  cp group_vars/vault.yml.example group_vars/vault.yml
  vim group_vars/vault.yml      # proxmox_api_token_secret (token) OR proxmox_api_password
  ansible-vault encrypt group_vars/vault.yml   # then run with --ask-vault-pass
  ```

## 6. Prove it on ONE box first

Build just the Win10 box — it has no domain dependency and exercises the two
parts most likely to need a tweak (virtio driver injection + WinRM):

```bash
ansible-playbook build.yml -e lab_vm_filter=danderspritz --ask-vault-pass
```

Open that VM's console in the PVE GUI and **watch the install**. The answer file
offers the virtio driver from the virtio-win CD across drive letters C:–H:
(`virtio_winpe_drives`), so Setup should find the disk automatically. If it still
reports it cannot find a disk (or "could not apply the DiskConfiguration"), press
`Shift+F10`, run `diskpart` → `list volume` to see the virtio CD's letter, and
widen `virtio_winpe_drives` in `roles/proxmox_vm/defaults/main.yml` if it's
outside that range, then retry. When it is up:

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

## Ways to run it

There are two phases and you can run them together or separately. `build.yml`
prompts (hidden) for the Proxmox secret unless you pass `-e proxmox_secret_prompt=…`
or keep it in a vault (add `--ask-vault-pass` only if you use a vault).

### The playbooks

| Command | What it does |
|---------|--------------|
| `ansible-playbook site.yml` | **Everything**: ensure the bridge (managed mode) → preflight ISOs/tools → build all VMs → configure all guests. The whole lab from scratch. |
| `ansible-playbook build.yml` | **Phase 1 only** (control node → Proxmox API): ensure the bridge, preflight, create the VMs from ISO + answer file (+ tools CD), power on, wait for WinRM. Idempotent — a VM whose `vmid` exists is left alone. |
| `ansible-playbook configure.yml` | **Phase 2 only** (over WinRM): common prep → DC promotion → target domain join → DanderSpritz box. Re-applies guest state; safe to re-run. |

### Scoping which hosts

| Flag | Applies to | Effect |
|------|-----------|--------|
| `-e lab_vm_filter=dc,target` | `build.yml` | Build only these VMs (comma list, or `all`). Unknown name fails early. Default `all`. |
| `--limit danderspritz` | `configure.yml` | Configure only this guest (inventory name: `dc`, `target`, `danderspritz`). |

> Note the asymmetry: `build.yml` loops a list on the control node, so it uses
> `-e lab_vm_filter=…`, **not** `--limit`. `configure.yml` targets real inventory
> hosts, so it uses `--limit`.

### Behaviour toggles (`-e VAR=…` on the command line, or in `group_vars`)

| Variable | Default | What it changes |
|----------|---------|-----------------|
| `proxmox_auth_method` | `token` | `token` (API token) or `password` (PVE login). See section 3. |
| `proxmox_secret_prompt` | *(prompted)* | The token secret / password. Pass `-e proxmox_secret_prompt=…` for unattended runs instead of typing it. |
| `lab_network_mode` | `managed` | `managed` / `existing` / `tagged` — see section 1. |
| `lab_vlan` | `""` | VLAN id for `tagged` mode. |
| `proxmox_lab_bridge` | `vmbr40` | Bridge to create (managed) or attach to (existing/tagged). |
| `proxmox_storage_check` | `true` | Validate `proxmox_disk_storage` (needs `images`) and `proxmox_iso_storage` (needs `iso`) against the node; if wrong, list the valid storages and prompt for a choice. `false` skips (unattended with known-good values). |
| `preflight_verify_sha256` | `true` | `false` skips the slow multi-GB ISO hashing (presence/name check still runs). |
| `preflight_check_isos` | `true` | `false` skips the ISO storage preflight entirely. |
| `fetch_eqgrp` *(per VM)* | `true` on DSZ | `false` → don't download the toolset to the CD; guest falls back to `git clone`. |
| `tools_iso` *(per VM)* | `true` on DSZ | whether to build/attach the vendored-installers CD. |
| `target_install_flare` | `true` | Attempt the FLARE RE tools on the Win7 target. They're optional and **non-fatal** (the old feed is dead — see `offline-assets.md`); `false` skips the step entirely. |

### Common recipes

```bash
# Full lab, from nothing
ansible-playbook site.yml --ask-vault-pass

# Prove the hard parts on one box first (virtio + WinRM), then configure it
ansible-playbook build.yml -e lab_vm_filter=danderspritz --ask-vault-pass
ansible-playbook configure.yml --limit danderspritz --ask-vault-pass

# Fast build — skip the ISO hashing (e.g. you already trust the storage)
ansible-playbook build.yml -e preflight_verify_sha256=false --ask-vault-pass

# Rebuild one box from scratch (destroy it in Proxmox first — build skips
# existing vmids)
ansible-playbook build.yml -e lab_vm_filter=target --ask-vault-pass
ansible-playbook configure.yml --limit target --ask-vault-pass

# Just re-run configuration on a host (no rebuild)
ansible-playbook configure.yml --limit dc --ask-vault-pass

# Use your own firewall VM on a tagged VLAN instead of host NAT
ansible-playbook site.yml -e lab_network_mode=tagged -e lab_vlan=40 \
  -e proxmox_lab_bridge=vmbr0 --ask-vault-pass
```
