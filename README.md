# The Adebayo Network Challenge
## Junction Track - June 2026

```bash
git clone https://github.com/Sammylee24/anc-junction-2026-06.git && cd anc-junction-2026-06 && bash setup.sh
```

---

## Overview

The Junction campus network is **broken**. 50 faults have been injected across routers and switches spanning Cisco IOS-XE and Juniper vJunos-evolved. Your job: find every fault, fix it, and submit proof.

Beyond the 50 faults, **8 hidden flags** are planted inside device container filesystems. Find them by exploring the lab environment.

**Duration:** 4 hours  
**Format:** Troubleshooting - find and fix injected faults  
**Difficulty:** CCNP level  
**Submit proof at:** https://challenges.samueladebayo.net

---

## Topology

```
        [ISP-R] --- 203.0.113.0/30 --- [JUN-R1]
                                            |
                                       10.0.12.0/30
                                            |
                                        [CORE-R1]
                                       /         \
                              10.0.13.0/30    10.0.14.0/30
                                 /                 \
                             [BR-R1]             [BR-R2]
                               |  \               |
                               |   \--------------+
                               |              [DIST-SW]
                               |                  |
                               +--------------[ACC-SW1]
                                                  |
                                               [PC1]
```

| Device   | Role                        | IP              | Credentials              |
|----------|-----------------------------|-----------------|--------------------------|
| ISP-R    | ISP router (no faults)      | 172.31.34.11    | admin / admin            |
| JUN-R1   | WAN border (Juniper)        | 172.31.34.12    | see JUN-R1 section below |
| CORE-R1  | Core router                 | 172.31.34.13    | admin / admin            |
| BR-R1    | Branch router 1             | 172.31.34.14    | admin / admin            |
| BR-R2    | Branch router 2             | 172.31.34.15    | admin / admin            |
| DIST-SW  | Distribution switch         | 172.31.34.21    | admin / admin            |
| ACC-SW1  | Access switch               | 172.31.34.22    | admin / admin            |
| PC1      | End host                    | 172.31.34.31    | root / admin             |

---

## Setup

### Requirements
- Linux (Ubuntu 20.04+ recommended) or macOS
- 8 GB RAM minimum (16 GB recommended)
- 20 GB free disk space
- Internet access (to pull Docker images)

The setup script will:
1. Clear any stale SSH host keys for lab IPs
2. Install Docker (if not present)
3. Install containerlab v0.74.3 (if not present)
4. Pull all required Docker images
5. Deploy the lab with faults pre-injected
6. Start autosave (config saved every 5 minutes to NVRAM)
7. Inject hidden flags into device filesystems

> **Note:** First-time image pulls may take 10-20 minutes depending on your connection. Cisco IOL devices are accessible via SSH ~60-90 seconds after deploy completes.

---

## JUN-R1 - Manual Config Step Required

JUN-R1 uses a Juniper vJunos-evolved QEMU image. Its faulted configuration **must be applied manually** after the lab deploys (the QEMU disk does not support bind-mounted startup configs).

**After `setup.sh` completes, wait ~3 minutes for JUN-R1 to boot:**

### Step 1 - Apply the faulted config (login as `admin`)

```
ssh admin@172.31.34.12
# password: admin@123
# (if prompted about host key: ssh-keygen -R 172.31.34.12)
```

Once logged in:

```
configure
load override terminal
[paste the full contents of configs/JUN-R1.conf]
^D
commit and-quit
```

### Step 2 - Troubleshoot (login as `root`)

After the faulted config is committed, the device is configured with `root` as the login user:

```
ssh root@172.31.34.12
# password: admin@123
```

---

## Fault Structure

| Tier   | Points | Count |
|--------|--------|-------|
| Easy   | 1 pt   | 20    |
| Medium | 2 pts  | 14    |
| Hard   | 4 pts  | 6     |

Faults span: VLANs, STP, OSPF, BGP, NTP, HSRP, NAT, GRE tunnels, IP SLA, DHCP, firewall filters, and redistribution loops.

---

## Hidden Flags

In addition to the 50 faults, **8 hidden flags** are planted inside the container filesystem of each device. They are worth 5 points each.

Find them by exploring the lab environment - each device has exactly one hidden flag at a unique path. Submit a discovered flag directly on the portal using the **Submit Hidden Flag** form (paste the raw `FLAG-XXXXXXXXXXXX` string).

---

## Submitting Proof

1. Run the diagnostic command shown in the challenge portal for each fault
2. Copy the CLI output
3. Paste it into the submission form at https://challenges.samueladebayo.net
4. Receive your FLAG token instantly

---

## Useful Tips

If you ever need to power-cycle a single device without touching the rest of the lab:

```bash
docker restart clab-junction-2026-06-<DEVICE>
# e.g.
docker restart clab-junction-2026-06-CORE-R1
```

The device will reload with whatever was last saved (`write memory`). SSH access resumes in ~30-60 seconds.

---

## Stopping the Lab

```bash
kill $(cat .autosave.pid) 2>/dev/null
sudo containerlab destroy --topo junction.clab.yml --cleanup
```

---

## Restarting from Scratch

```bash
bash setup.sh
```

---

*The Adebayo Network Challenge - challenges.samueladebayo.net*
