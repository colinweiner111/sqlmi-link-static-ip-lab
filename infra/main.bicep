// ============================================================================
// main.bicep — SQL MI — Static IP Gateway
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

@description('VM SKU for HAProxy and client VMs')
param vmSize string = 'Standard_D2s_v5'

@description('Static frontend IP for the load balancer (must be in proxy-subnet 10.0.1.0/24)')
param lbFrontendIp string = '10.0.1.10'

@description('SQL Managed Instance name (must be globally unique)')
param sqlMiName string = 'sqlmi-link-lab-${uniqueString(resourceGroup().id)}'

@description('Entra admin object ID for SQL MI (required in lab mode)')
param entraAdminObjectId string = ''

@description('Entra admin login (UPN) for SQL MI (required in lab mode)')
param entraAdminLogin string = ''

@description('Tenant ID for Entra authentication (required in lab mode)')
param tenantId string = ''

@description('Deployment mode: "lab" deploys the full validation environment including VNets, SQL MI, and client VMs. "existing" deploys only HAProxy + LB into an existing subnet pointing at an existing SQL MI.')
@allowed(['lab', 'existing'])
param deployMode string = 'lab'

@description('(existing mode only) Resource ID of the subnet to deploy the HAProxy VMs and LB into')
param existingProxySubnetId string = ''

@description('(existing mode only) FQDN of the existing SQL Managed Instance (e.g. mymi.abc123.database.windows.net)')
param existingMiFqdn string = ''

@description('(existing mode only) An available static private IP within the existing subnet for the LB frontend')
param existingLbFrontendIp string = ''

@description('Set to false when the proxy subnet already has outbound internet via Azure Firewall, on-prem routing, or another NAT solution')
param deployNatGateway bool = true

@description('Set to false to skip deploying the test client VM (useful in existing mode when you already have a test machine)')
param deployClientVm bool = true

// ============================================================================
// 1. Networking — Two VNets + Peering + NSGs  (lab mode only)
// ============================================================================
module networking 'vnet.bicep' = if (deployMode == 'lab') {
  name: 'deploy-networking'
  params: {
    location: location
    deployNatGateway: deployNatGateway
  }
}

// ============================================================================
// 2. Azure SQL Managed Instance — Free tier (Freemium)  (lab mode only)
//    Takes 30-60 minutes to provision
// ============================================================================
module sqlmi 'sql-mi.bicep' = if (deployMode == 'lab') {
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
    proxySubnetId: deployMode == 'lab' ? networking.outputs.proxySubnetId : existingProxySubnetId
    frontendIp: deployMode == 'lab' ? lbFrontendIp : existingLbFrontendIp
  }
}

// ============================================================================
// 4. HAProxy VM — L4 TCP proxy
// ============================================================================
module proxyVm 'proxy-vm.bicep' = {
  name: 'deploy-proxy-vm'
  params: {
    location: location
    proxySubnetId: deployMode == 'lab' ? networking.outputs.proxySubnetId : existingProxySubnetId
    adminUsername: adminUsername
    adminPasswordOrKey: adminPassword
    authenticationType: 'password'
    vmSize: vmSize
    instanceCount: 2
    sqlmiFqdn: deployMode == 'lab' ? sqlmi.outputs.miFqdn : existingMiFqdn
    lbBackendPoolId: lb.outputs.backendPoolId
  }
}

// ============================================================================
// 5. Client VM — test client (lab: client-subnet / existing: same subnet as HAProxy)
// ============================================================================
module clientVm 'client-vm.bicep' = if (deployClientVm) {
  name: 'deploy-client-vm'
  params: {
    location: location
    clientSubnetId: deployMode == 'lab' ? networking.outputs.clientSubnetId : existingProxySubnetId
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
output clientPublicIp string = deployClientVm ? clientVm.outputs.publicIp : ''
output sqlmiFqdn string = deployMode == 'lab' ? sqlmi.outputs.miFqdn : existingMiFqdn
output sqlmiName string = deployMode == 'lab' ? sqlmi.outputs.miName : 'N/A - existing mode'
