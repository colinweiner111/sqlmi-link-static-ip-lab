// ============================================================================
// main.bicep — SQL MI Link Static IP Lab
// ============================================================================
// Deploys the full validation environment:
//   - Two VNets with peering (Azure-side + Client-side)
//   - NSGs with TCP 5022 rules
//   - Free-tier Azure SQL Managed Instance (real MI, port 5022)
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
param entraAdminObjectId string = 'ENTRA_ADMIN_OBJECT_ID_REMOVED'

@description('Entra admin login (UPN) for SQL MI')
param entraAdminLogin string = 'ENTRA_ADMIN_LOGIN_REMOVED'

@description('Tenant ID for Entra authentication')
param tenantId string = 'TENANT_ID_REMOVED'

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
// 2. Azure SQL Managed Instance — Free tier (Freemium)
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
// 3. Load Balancer — Static private IP entry point
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
// 4. HAProxy VM — L4 TCP proxy
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
// 5. Client VM — Simulates on-premises SQL Server
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
