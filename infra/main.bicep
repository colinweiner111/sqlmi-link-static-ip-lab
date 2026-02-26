// ============================================================================
// main.bicep — SQL MI Link Static IP Lab
// ============================================================================
// Deploys the full validation environment:
//   - Two VNets with peering (Azure-side + Client-side)
//   - NSGs with TCP 5022 rules
//   - Free-tier Azure SQL Managed Instance (real MI, port 5022)
//   - Simulated backend VMs (fallback for quick testing)
//   - HAProxy VM (L4 TCP proxy resolving MI FQDN)
//   - Internal Standard Load Balancer (static private IP)
//   - Client VM in separate VNet (simulates AWS-side SQL Server)
// ============================================================================

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Admin username for all VMs')
param adminUsername string

@secure()
@description('Admin password for all VMs')
param adminPassword string

@description('VM SKU — B1s is sufficient for this lab')
param vmSize string = 'Standard_B1s'

@description('Static frontend IP for the load balancer (must be in proxy-subnet 10.0.1.0/24)')
param lbFrontendIp string = '10.0.1.10'

@description('SQL Managed Instance name (must be globally unique)')
param sqlMiName string = 'sqlmi-link-lab-${uniqueString(resourceGroup().id)}'

@description('Entra admin object ID for SQL MI')
param entraAdminObjectId string = '80372b20-91ae-491c-8242-2b77f22448bd'

@description('Entra admin login (UPN) for SQL MI')
param entraAdminLogin string = 'admin@MngEnvMCAP021962.onmicrosoft.com'

@description('Tenant ID for Entra authentication')
param tenantId string = '14383c24-7c86-4a21-b19a-ba7f37d27f8e'

// ============================================================================
// 1. Networking — Two VNets + Peering + NSGs
// ============================================================================
module networking 'vnet.bicep' = {
  name: 'deploy-networking'
  params: {
    location: location
  }
}

// ============================================================================
// 2. Private DNS Zone — Simulates SQL MI FQDN (linked to both VNets)
//    Kept for fallback testing with simulated backend VMs
// ============================================================================
module dns 'private-dns.bicep' = {
  name: 'deploy-dns'
  params: {
    azureVnetId: networking.outputs.azureVnetId
    clientVnetId: networking.outputs.clientVnetId
    initialBackendIp: '10.0.2.4' // Points to vm-sql-a initially
  }
}

// ============================================================================
// 3. Azure SQL Managed Instance — Free tier (Freemium)
//    Takes 30-60 minutes to provision
// ============================================================================
module sqlmi 'sql-mi.bicep' = {
  name: 'deploy-sql-mi'
  params: {
    location: location
    miSubnetId: networking.outputs.miSubnetId
    miName: sqlMiName
    adminLogin: adminUsername
    adminPassword: adminPassword
    entraAdminObjectId: entraAdminObjectId
    entraAdminLogin: entraAdminLogin
    tenantId: tenantId
  }
}

// ============================================================================
// 4. Backend VMs — Simulated SQL MI endpoints (fallback for quick testing)
// ============================================================================
module backendVms 'backend-vms.bicep' = {
  name: 'deploy-backend-vms'
  params: {
    location: location
    backendSubnetId: networking.outputs.backendSubnetId
    adminUsername: adminUsername
    adminPasswordOrKey: adminPassword
    authenticationType: 'password'
    vmSize: vmSize
  }
}

// ============================================================================
// 5. Load Balancer — Static private IP entry point
// ============================================================================
module lb 'load-balancer.bicep' = {
  name: 'deploy-load-balancer'
  params: {
    location: location
    proxySubnetId: networking.outputs.proxySubnetId
    frontendIp: lbFrontendIp
  }
}

// ============================================================================
// 6. HAProxy VM — L4 TCP proxy
//    Uses the real MI FQDN as backend target
// ============================================================================
module proxyVm 'proxy-vm.bicep' = {
  name: 'deploy-proxy-vm'
  params: {
    location: location
    proxySubnetId: networking.outputs.proxySubnetId
    adminUsername: adminUsername
    adminPasswordOrKey: adminPassword
    authenticationType: 'password'
    vmSize: vmSize
    sqlmiFqdn: sqlmi.outputs.miFqdn
    lbBackendPoolId: lb.outputs.backendPoolId
  }
}

// ============================================================================
// 7. Client VM — Simulates AWS SQL Server
// ============================================================================
module clientVm 'client-vm.bicep' = {
  name: 'deploy-client-vm'
  params: {
    location: location
    clientSubnetId: networking.outputs.clientSubnetId
    adminUsername: adminUsername
    adminPasswordOrKey: adminPassword
    authenticationType: 'password'
    vmSize: vmSize
  }
}

// ============================================================================
// Outputs
// ============================================================================
output lbStaticIp string = lb.outputs.frontendStaticIp
output clientPublicIp string = clientVm.outputs.publicIp
output sqlmiFqdn string = sqlmi.outputs.miFqdn
output sqlmiName string = sqlmi.outputs.miName
output simulatedFqdn string = dns.outputs.fqdn
output backendVmAIp string = backendVms.outputs.vmAPrivateIp
output backendVmBIp string = backendVms.outputs.vmBPrivateIp
