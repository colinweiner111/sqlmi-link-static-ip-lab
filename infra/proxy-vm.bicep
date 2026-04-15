// ============================================================================
// HAProxy VM — L4 TCP proxy forwarding 5022 + 1433 + 11000-11999 via FQDN
// ============================================================================

param location string
param proxySubnetId string
param adminUsername string
@secure()
param adminPasswordOrKey string
param sqlmiFqdn string
param lbBackendPoolId string = ''

@allowed(['password', 'sshPublicKey'])
param authenticationType string = 'password'

@description('Number of HAProxy VMs to deploy (2 = active/active behind LB)')
@minValue(1)
@maxValue(4)
param instanceCount int = 2

param vmSize string = 'Standard_B1s'

// ---- cloud-init: install HAProxy with TCP 5022 + 1433 + 11000-11999 config ----
// Uses __SQLMI_FQDN__ as a placeholder, replaced by Bicep before encoding
var cloudInitScript = '''#cloud-config
package_update: true
packages:
  - haproxy
write_files:
  - path: /etc/haproxy/haproxy.cfg
    content: |
      global
          log /dev/log local0
          maxconn 4096
          stats socket /run/haproxy/admin.sock mode 660 level admin

      defaults
          log     global
          mode    tcp
          timeout connect 10s
          timeout client  1h
          timeout server  1h

      resolvers azure
          nameserver dns1 168.63.129.16:53
          resolve_retries 3
          timeout resolve 1s
          hold valid 10s

      # --- MI Link (database mirroring) ---
      frontend sqlmi_link_frontend
          bind *:5022
          default_backend sqlmi_link_backend

      backend sqlmi_link_backend
          server sqlmi-link __SQLMI_FQDN__:5022 check resolvers azure resolve-prefer ipv4

      # --- SQL client connections (TDS) ---
      frontend sqlmi_tds_frontend
          bind *:1433
          default_backend sqlmi_tds_backend

      backend sqlmi_tds_backend
          server sqlmi-tds __SQLMI_FQDN__:1433 check resolvers azure resolve-prefer ipv4

      # --- MI redirect ports (connection policy = Redirect) ---
      # Client connects on a specific port in 11000-11999; HAProxy
      # forwards to the same port on MI. Uses 'port 0' so the backend
      # connects on the same port the frontend received.
      frontend sqlmi_redirect_frontend
          bind *:11000-11999
          default_backend sqlmi_redirect_backend

      backend sqlmi_redirect_backend
          server sqlmi-redir __SQLMI_FQDN__ resolvers azure resolve-prefer ipv4

      # --- Stats dashboard (internal only, port 8404) ---
      listen stats
          bind *:8404
          mode http
          stats enable
          stats uri /stats
          stats refresh 5s
          stats show-legends
          stats show-node
runcmd:
  - systemctl enable haproxy
  - systemctl restart haproxy
'''

// Replace placeholder with actual FQDN parameter value
var cloudInitFinal = replace(cloudInitScript, '__SQLMI_FQDN__', sqlmiFqdn)

var linuxConfiguration = authenticationType == 'sshPublicKey' ? {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
} : null

var lbBackendPools = empty(lbBackendPoolId) ? [] : [
  {
    id: lbBackendPoolId
  }
]

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, instanceCount): {
  name: 'nic-vm-haproxy-${i + 1}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: proxySubnetId
          }
          loadBalancerBackendAddressPools: lbBackendPools
        }
      }
    ]
  }
}]

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, instanceCount): {
  name: 'vm-haproxy-${i + 1}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'vm-haproxy-${i + 1}'
      adminUsername: adminUsername
      adminPassword: authenticationType == 'password' ? adminPasswordOrKey : null
      linuxConfiguration: linuxConfiguration
      customData: base64(cloudInitFinal)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic[i].id
        }
      ]
    }
  }
}]

// ---- Outputs ----
output vmNames array = [for i in range(0, instanceCount): vm[i].name]
output privateIps array = [for i in range(0, instanceCount): nic[i].properties.ipConfigurations[0].properties.privateIPAddress]
