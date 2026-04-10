// ============================================================================
// Networking — Two VNets + Peering + NSGs
// ============================================================================
// vnet-azure  (10.0.0.0/16) — Azure side: LB + HAProxy + SQL MI
// vnet-client (10.1.0.0/16) — Simulates on-premises network: Client VM
// Peering connects them to simulate cross-network reachability via static IP.
// ============================================================================

param location string

@description('Set to false if the subnet already has outbound internet via Azure Firewall, on-prem routing, or another NAT solution')
param deployNatGateway bool = true

// ---- Azure-side VNet ----
param azureVnetName string = 'vnet-azure'
param azureVnetPrefix string = '10.0.0.0/16'

param proxySubnetName string = 'proxy-subnet'
param proxySubnetPrefix string = '10.0.1.0/24'

// ---- SQL MI subnet (delegated) ----
param miSubnetName string = 'mi-subnet'
param miSubnetPrefix string = '10.0.4.0/24'

// ---- Client-side VNet (simulates AWS network) ----
param clientVnetName string = 'vnet-client'
param clientVnetPrefix string = '10.1.0.0/16'

param clientSubnetName string = 'client-subnet'
param clientSubnetPrefix string = '10.1.1.0/24'

// ============================================================================
// NSGs
// ============================================================================

// ---- NSG: Proxy Subnet ----
resource nsgProxy 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-proxy'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-5022-From-Client'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: clientSubnetPrefix
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-1433-From-Client'
        properties: {
          priority: 105
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: clientSubnetPrefix
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-5022-From-LB'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-1433-From-LB'
        properties: {
          priority: 115
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-Redirect-From-Client'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '11000-11999'
          sourceAddressPrefix: clientSubnetPrefix
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-Redirect-From-LB'
        properties: {
          priority: 125
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '11000-11999'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-Stats-From-Client'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8404'
          sourceAddressPrefix: clientSubnetPrefix
          destinationAddressPrefix: proxySubnetPrefix
        }
      }
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ---- NSG: Client Subnet ----
resource nsgClient 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-client'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ---- NSG: SQL MI Subnet ----
// Service-aided configuration adds most required rules automatically.
// We add the rules needed for our lab (5022 from HAProxy + management).
resource nsgMi 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-mi'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-5022-From-Proxy'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5022'
          sourceAddressPrefix: proxySubnetPrefix
          destinationAddressPrefix: miSubnetPrefix
        }
      }
      {
        name: 'Allow-1433-From-Proxy'
        properties: {
          priority: 105
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: proxySubnetPrefix
          destinationAddressPrefix: miSubnetPrefix
        }
      }
      {
        name: 'Allow-Redirect-From-Proxy'
        properties: {
          priority: 107
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '11000-11999'
          sourceAddressPrefix: proxySubnetPrefix
          destinationAddressPrefix: miSubnetPrefix
        }
      }
      {
        name: 'Allow-Management-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9000-9999'
          sourceAddressPrefix: 'SqlManagement'
          destinationAddressPrefix: miSubnetPrefix
        }
      }
      {
        name: 'Allow-HealthProbe-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: miSubnetPrefix
        }
      }
      {
        name: 'Allow-MI-Internal-Inbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: miSubnetPrefix
          destinationAddressPrefix: miSubnetPrefix
        }
      }
      {
        name: 'Allow-MI-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: miSubnetPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ---- NAT Gateway — Outbound internet for proxy subnet ----
// VMs without public IPs need a NAT Gateway for outbound access
// (apt package installs via cloud-init, etc.)
// Skip if the subnet already has outbound internet via Azure Firewall or on-prem routing.
resource natGwPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployNatGateway) {
  name: 'pip-natgw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGw 'Microsoft.Network/natGateways@2024-05-01' = if (deployNatGateway) {
  name: 'natgw-lab'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natGwPip.id
      }
    ]
    idleTimeoutInMinutes: 4
  }
}

// ============================================================================
// Route Table for SQL MI Subnet
// ============================================================================
// SQL MI requires a route table associated with its subnet.
// Service-aided configuration adds management routes automatically.
// We must include the mi-subnet → VnetLocal route so that redeployments
// don't conflict with SQL MI's NetworkIntentPolicy requirements.
resource rtMi 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-mi-subnet'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'mi-subnet-to-vnetlocal'
        properties: {
          addressPrefix: miSubnetPrefix
          nextHopType: 'VnetLocal'
        }
      }
    ]
  }
}

// ============================================================================
// VNets
// ============================================================================

// ---- Azure-side VNet (proxy + MI subnets) ----
resource vnetAzure 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: azureVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        azureVnetPrefix
      ]
    }
    subnets: [
      {
        name: proxySubnetName
        properties: {
          addressPrefix: proxySubnetPrefix
          networkSecurityGroup: {
            id: nsgProxy.id
          }
          natGateway: deployNatGateway ? { id: natGw.id } : null
        }
      }
      {
        name: miSubnetName
        properties: {
          addressPrefix: miSubnetPrefix
          networkSecurityGroup: {
            id: nsgMi.id
          }
          routeTable: {
            id: rtMi.id
          }
          delegations: [
            {
              name: 'managedInstanceDelegation'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

// ---- Client-side VNet (simulates AWS network) ----
resource vnetClient 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: clientVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        clientVnetPrefix
      ]
    }
    subnets: [
      {
        name: clientSubnetName
        properties: {
          addressPrefix: clientSubnetPrefix
          networkSecurityGroup: {
            id: nsgClient.id
          }
          defaultOutboundAccess: true
        }
      }
    ]
  }
}

// ============================================================================
// VNet Peering (bidirectional)
// ============================================================================

// Azure → Client
resource peeringAzureToClient 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: vnetAzure
  name: 'peer-azure-to-client'
  properties: {
    remoteVirtualNetwork: {
      id: vnetClient.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Client → Azure
resource peeringClientToAzure 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: vnetClient
  name: 'peer-client-to-azure'
  properties: {
    remoteVirtualNetwork: {
      id: vnetAzure.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ============================================================================
// Outputs
// ============================================================================
output azureVnetId string = vnetAzure.id
output azureVnetName string = vnetAzure.name
output clientVnetId string = vnetClient.id
output clientVnetName string = vnetClient.name
output proxySubnetId string = vnetAzure.properties.subnets[0].id
output miSubnetId string = vnetAzure.properties.subnets[1].id
output clientSubnetId string = vnetClient.properties.subnets[0].id
