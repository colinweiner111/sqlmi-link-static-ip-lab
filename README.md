# SQL MI Link Static IP Validation Lab

## Problem Statement

A customer's AWS-to-Azure VPN/firewall requires a **single, fixed destination IP** on the Azure side for allow-listing and security inspection. SQL Managed Instance Link replication uses **TCP port 5022**, and the SQL MI FQDN resolves to an IP within the MI subnet that **can change** during maintenance or failover events.

The product team proposed using **Azure Application Gateway** to map frontend `:5022` to backend `:5022` using the MI FQDN as the target.

### Why Application Gateway Won't Work

**Azure Application Gateway is a Layer 7 (HTTP/HTTPS) load balancer.** It cannot proxy raw TCP traffic.

| Capability | Application Gateway | Required |
|---|---|---|
| HTTP/HTTPS proxy | Yes | No |
| WebSocket proxy | Yes | No |
| Raw TCP forwarding | **No** | **Yes** |
| Port 5022 (TDS/DB mirroring) | **Not supported** | **Required** |

SQL MI Link replication uses the TDS + database mirroring protocol on TCP 5022. This is not HTTP/HTTPS traffic. Application Gateway would fail immediately.

**Verdict: Right pattern, wrong Azure service.**

### Why Private Endpoint Doesn't Solve This Either

| Scenario | Port | Private Endpoint Support |
|---|---|---|
| SQL MI standard connectivity | 1433 | Yes |
| SQL MI Link / AG replication | **5022** | **No** |

Private Endpoint for SQL MI only supports port 1433, making it unsuitable for MI Link scenarios.

---

## Correct Architecture

The validated pattern uses an **Internal Standard Load Balancer** + **HAProxy TCP proxy VM**:

![SQL MI Link Static IP Architecture](image/sqlmi-link-static-ip-diagram.drawio.svg)

### Why This Works

| Requirement | How It's Met |
|---|---|
| Single static IP for VPN allow-list | Load Balancer frontend: `10.0.1.10` |
| TCP 5022 forwarding | LB rule + HAProxy `mode tcp` |
| Backend defined by FQDN | HAProxy `resolvers azure` with `hold valid 10s` |
| Backend IP can change | HAProxy re-resolves FQDN automatically |
| No client-side changes needed | Static IP never changes |

---

## Lab Environment

This lab deploys a **real Azure SQL Managed Instance (free tier)** behind an HAProxy TCP proxy and Internal Standard LB, proving the static IP pattern works end-to-end.

A simulated backend (2 VMs with socat on 5022 + Private DNS) is also deployed as a fast-validation fallback that doesn't require the 30-60 minute MI provisioning time.

### Network Layout

The lab uses **two VNets with bidirectional peering** to simulate the AWS ↔ Azure network boundary:

| VNet | CIDR | Simulates |
|---|---|---|
| `vnet-azure` | 10.0.0.0/16 | Azure side (LB + proxy + SQL MI) |
| `vnet-client` | 10.1.0.0/16 | AWS / remote network |

| Component | VNet | Subnet | IP |
|---|---|---|---|
| Load Balancer frontend | vnet-azure | proxy-subnet (10.0.1.0/24) | 10.0.1.10 (static) |
| HAProxy VM | vnet-azure | proxy-subnet (10.0.1.0/24) | Dynamic |
| **SQL Managed Instance** | **vnet-azure** | **mi-subnet (10.0.4.0/24)** | **Dynamic (FQDN-resolved)** |
| Backend VM A (fallback) | vnet-azure | backend-subnet (10.0.2.0/24) | 10.0.2.4 (static) |
| Backend VM B (fallback) | vnet-azure | backend-subnet (10.0.2.0/24) | 10.0.2.5 (static) |
| Client VM | vnet-client | client-subnet (10.1.1.0/24) | Dynamic + Public IP |

VNet peering allows the client to reach the LB static IP across the network boundary, simulating VPN reachability.

### NSG Rules (TCP 5022)

| Source | Destination | Port | Purpose |
|---|---|---|---|
| client-subnet | proxy-subnet | 5022 | Client → LB → HAProxy |
| AzureLoadBalancer | proxy-subnet | 5022 | Health probes |
| proxy-subnet | backend-subnet | 5022 | HAProxy → Backend VMs (fallback) |
| proxy-subnet | mi-subnet | 5022 | HAProxy → SQL MI |

### DNS

- **Real MI FQDN:** `<mi-name>.database.windows.net` (auto-created by SQL MI)
- **Simulated zone (fallback):** `fake-sqlmi.database.windows.net` (Private DNS, linked to both VNets)
- **Simulated record:** `sqlmi-test` → `10.0.2.4` (initial, TTL 10s)

### HAProxy Configuration

```
mode    tcp

resolvers azure
    nameserver dns1 168.63.129.16:53
    hold valid 10s

backend sqlmi_backend
    server sqlmi sqlmi-test.fake-sqlmi.database.windows.net:5022 check resolvers azure resolve-prefer ipv4
```

Key settings:
- `mode tcp` — Layer 4 forwarding (not HTTP)
- `resolvers azure` — Uses Azure's internal DNS (`168.63.129.16`)
- `hold valid 10s` — Re-resolves the FQDN every 10 seconds
- `resolve-prefer ipv4` — Ensures IPv4 resolution

---

## Deployment

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- Contributor access to an Azure subscription

### Deploy

```powershell
.\scripts\deploy.ps1 `
    -ResourceGroupName "rg-sqlmi-link-lab" `
    -Location "westus3" `
    -AdminUsername "azureuser" `
    -AdminPassword (ConvertTo-SecureString "YourP@ssword123!" -AsPlainText -Force)
```

### Current Deployment Details

| Resource | Value |
|---|---|
| Resource Group | `rg-sqlmi-link-lab` |
| Region | `westus3` |
| Admin Username | `azureuser` |
| Admin Password | *(set during deployment — check `deploy.ps1` params)* |
| LB Static IP | `10.0.1.10` |
| Client VM Public IP | *(check deployment outputs)* |
| SQL MI FQDN (real) | *(check deployment outputs — `sqlmiFqdn`)* |
| SQL MI FQDN (simulated) | `sqlmi-test.fake-sqlmi.database.windows.net` |
| Backend VM-A IP | `10.0.2.4` |
| Backend VM-B IP | `10.0.2.5` |
| Auth Mode | **Entra-only** (corporate policy) |

### What Gets Deployed

| Resource | Type | Purpose |
|---|---|---|
| vnet-azure | Virtual Network | 10.0.0.0/16 — Azure side (proxy + backend + MI subnets) |
| vnet-client | Virtual Network | 10.1.0.0/16 — Simulated AWS network (client subnet) |
| peer-azure-to-client / peer-client-to-azure | VNet Peering | Bidirectional connectivity |
| nsg-proxy / nsg-backend / nsg-mi / nsg-client | NSGs | TCP 5022 allow rules |
| **SQL Managed Instance (free tier)** | **SQL MI** | **Real MI Link endpoint on port 5022** |
| fake-sqlmi.database.windows.net | Private DNS Zone | Simulates SQL MI FQDN (fallback testing) |
| vm-sql-a, vm-sql-b | Linux VMs | Simulated SQL MI fallback (socat on 5022) |
| vm-haproxy | Linux VM | L4 TCP proxy |
| lb-sqlmi-proxy | Standard Load Balancer | Static IP entry point |
| vm-client | Linux VM | Test client (with public IP for SSH) |

---

## Testing

### Test 1 — Real SQL MI Connectivity (Port 5022)

SSH into the client VM and connect to the load balancer's static IP on port 5022:

```bash
ssh azureuser@<client-public-ip>
nc -zv 10.0.1.10 5022
```

**Expected:** Connection succeeds. Traffic path:  
Client (vnet-client) → Peering → LB (10.0.1.10) → HAProxy → real SQL MI FQDN → MI subnet (10.0.4.0/24)

### Test 2 — Verify HAProxy FQDN Resolution

SSH into the HAProxy VM and verify it's resolving the real MI FQDN:

```bash
# From HAProxy VM
echo "show servers state" | sudo socat stdio /run/haproxy/admin.sock
nslookup <mi-fqdn> 168.63.129.16
```

### Test 3 — Fallback Testing with Simulated Backend

If you want to test DNS failover without waiting for MI provisioning, use the simulated backend:

1. Reconfigure HAProxy to point to the fake FQDN:
   ```bash
   # On vm-haproxy, edit /etc/haproxy/haproxy.cfg
   # Change the backend server line to use:
   #   sqlmi-test.fake-sqlmi.database.windows.net:5022
   sudo systemctl restart haproxy
   ```

2. Test connectivity:
   ```bash
   # From client VM
   nc 10.0.1.10 5022
   # → Connected to vm-sql-a
   ```

3. Switch DNS to VM B:
   ```powershell
   .\scripts\switch-backend.ps1 -ResourceGroupName "rg-sqlmi-link-lab" -TargetIp "10.0.2.5"
   ```

4. Wait ~15 seconds for HAProxy to re-resolve, then test again:
   ```bash
   nc 10.0.1.10 5022
   # → Connected to vm-sql-b
   ```

The client still connects to the **same static IP** (`10.0.1.10`) but traffic reaches a different backend.

---

## Success Criteria

| Criteria | Status |
|---|---|
| Single static IP presented to external networks | `10.0.1.10` via Standard LB |
| TCP 5022 forwarding works end-to-end | LB → HAProxy → backend |
| Cross-VNet reachability via peering | Client in vnet-client reaches LB in vnet-azure |
| Backend IP changes handled via DNS re-resolution | HAProxy `hold valid 10s` |
| No client-side changes when backend IP changes | Static LB frontend IP unchanged |

---

## Production Pattern

For the real customer deployment, replace the test components:

```
AWS SQL Server
     │
     │ Site-to-Site VPN (allow-list: static LB IP)
     ▼
Azure Standard Load Balancer (static private IP)
     │
     ▼
HAProxy / Envoy VM(s) — TCP proxy tier
     │ (FQDN-based backend)
     ▼
Azure SQL Managed Instance (real MI FQDN)
     └─ Port 5022 (MI Link / AG replication)
```

### Production Considerations

- **HA for the proxy tier:** Deploy 2+ HAProxy VMs behind the LB for redundancy
- **Monitoring:** HAProxy stats page + Azure Monitor for LB health
- **Alternatives to HAProxy:** Envoy, NGINX stream module, or a small NVA
- **Azure Firewall DNAT:** Possible but heavier/more expensive than a proxy VM
- **Keepalived:** Can be used alongside HAProxy for additional failover

---

## Cleanup

```powershell
.\scripts\cleanup.ps1 -ResourceGroupName "rg-sqlmi-link-lab"
```

---

## File Structure

```
sqlmi-link-static-ip-lab/
├── README.md                          # This file
├── infra/
│   ├── main.bicep                     # Orchestration — deploys everything
│   ├── vnet.bicep                     # Two VNets + peering + NSGs + MI subnet
│   ├── private-dns.bicep              # Private DNS zone + A record (fallback)
│   ├── sql-mi.bicep                   # Azure SQL MI (free tier, Entra-only auth)
│   ├── backend-vms.bicep              # 2 backend VMs (simulated SQL MI fallback)
│   ├── proxy-vm.bicep                 # HAProxy VM with cloud-init
│   ├── load-balancer.bicep            # Internal Standard LB (static IP)
│   └── client-vm.bicep                # Client VM with public IP
└── scripts/
    ├── deploy.ps1                     # One-command deployment
    ├── switch-backend.ps1             # Simulate SQL MI IP change (fallback mode)
    └── cleanup.ps1                    # Delete resource group
```
