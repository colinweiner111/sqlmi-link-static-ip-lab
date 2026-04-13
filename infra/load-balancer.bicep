// ============================================================================
// Internal Standard Load Balancer — Static private IP (TCP 5022 + 1433 + 11000-11999)
// ============================================================================
// This is the single static IP that the VPN/firewall allow-lists.
// It load-balances to the HAProxy VM which handles FQDN-based forwarding.
// Uses HA Ports rule to forward all TCP traffic (covers 5022, 1433, and
// the MI redirect port range 11000-11999).
// ============================================================================

param location string
param proxySubnetId string
param frontendIp string = '10.0.1.10'

// ---- Load Balancer ----
resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: 'lb-sqlmi-proxy'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-static-ip'
        properties: {
          privateIPAddress: frontendIp
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: proxySubnetId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'be-haproxy'
      }
    ]
    probes: [
      {
        name: 'probe-tcp-5022'
        properties: {
          protocol: 'Tcp'
          port: 5022
          intervalInSeconds: 15
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-ha-ports'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-sqlmi-proxy', 'fe-static-ip')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-sqlmi-proxy', 'be-haproxy')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-sqlmi-proxy', 'probe-tcp-5022')
          }
          protocol: 'All'
          frontendPort: 0
          backendPort: 0
          enableFloatingIP: false
          idleTimeoutInMinutes: 30
          loadDistribution: 'Default'
          enableTcpReset: true
        }
      }
    ]
  }
}

// ---- Outputs ----
output lbName string = lb.name
output frontendStaticIp string = frontendIp
output lbId string = lb.id
output backendPoolId string = lb.properties.backendAddressPools[0].id
