// ============================================================================
// HAProxy VM — L4 TCP proxy forwarding port 5022 via FQDN
// ============================================================================

param location string
param proxySubnetId string
param adminUsername string
@secure()
param adminPasswordOrKey string
param sqlmiFqdn string = 'sqlmi-test.fake-sqlmi.database.windows.net'
param lbBackendPoolId string = ''

@allowed(['password', 'sshPublicKey'])
param authenticationType string = 'password'

param vmSize string = 'Standard_B1s'

// ---- cloud-init: install HAProxy with TCP 5022 forwarding config ----
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

      frontend sqlmi_frontend
          bind *:5022
          default_backend sqlmi_backend

      backend sqlmi_backend
          server sqlmi __SQLMI_FQDN__:5022 check resolvers azure resolve-prefer ipv4
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

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-vm-haproxy'
  location: location
  properties: {
    enableIPForwarding: true
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
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-haproxy'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'vm-haproxy'
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
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ---- Outputs ----
output vmName string = vm.name
output nicId string = nic.id
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
