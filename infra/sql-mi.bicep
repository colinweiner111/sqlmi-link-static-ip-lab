// ============================================================================
// Azure SQL Managed Instance — Free tier (Freemium)
// ============================================================================
// Deploys a free SQL MI instance for validating the MI Link static IP pattern.
// Free tier: GP_Gen5, 4 vCores, 64 GB storage, $0/month.
// Provisioning takes 30-60 minutes.
//
// Note: Corporate policy (MCAPSGov) requires Entra-only authentication.
//       SQL auth credentials are still passed but Entra admin is primary.
// ============================================================================

param location string
param miSubnetId string

@description('SQL MI instance name (must be globally unique)')
param miName string

@description('SQL MI SQL admin username (required by ARM but Entra-only auth is enforced)')
param adminLogin string

@secure()
@description('SQL MI SQL admin password')
param adminPassword string

@description('Entra admin object ID (user or group)')
param entraAdminObjectId string

@description('Entra admin login (UPN or group name)')
param entraAdminLogin string

@description('Tenant ID for Entra authentication')
param tenantId string

resource sqlmi 'Microsoft.Sql/managedInstances@2025-01-01' = {
  name: miName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 4
  }
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdminLogin
      principalType: 'User'
      sid: entraAdminObjectId
      tenantId: tenantId
    }
    subnetId: miSubnetId
    storageSizeInGB: 64
    vCores: 4
    licenseType: 'LicenseIncluded'
    pricingModel: 'Freemium'
    publicDataEndpointEnabled: false
    zoneRedundant: false
    databaseFormat: 'SQLServer2025'
  }
}

// ---- Outputs ----
output miId string = sqlmi.id
output miName string = sqlmi.name
output miFqdn string = sqlmi.properties.fullyQualifiedDomainName
