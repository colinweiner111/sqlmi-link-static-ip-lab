// ============================================================================
// Private DNS Zone — Simulates SQL MI FQDN resolution
// ============================================================================

param dnsZoneName string = 'fake-sqlmi.database.windows.net'
param recordName string = 'sqlmi-test'
param initialBackendIp string = '10.0.2.4'
param azureVnetId string
param clientVnetId string

// ---- Private DNS Zone ----
resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: dnsZoneName
  location: 'global'
}

// ---- VNet Link: Azure VNet (HAProxy needs to resolve the FQDN) ----
resource azureVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZone
  name: 'link-to-azure-vnet'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: azureVnetId
    }
    registrationEnabled: false
  }
}

// ---- VNet Link: Client VNet (optional — allows client to resolve FQDN too) ----
resource clientVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZone
  name: 'link-to-client-vnet'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: clientVnetId
    }
    registrationEnabled: false
  }
}

// ---- A Record pointing to initial backend VM ----
resource aRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: dnsZone
  name: recordName
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: initialBackendIp
      }
    ]
  }
}

// ---- Outputs ----
output dnsZoneId string = dnsZone.id
output fqdn string = '${recordName}.${dnsZoneName}'
