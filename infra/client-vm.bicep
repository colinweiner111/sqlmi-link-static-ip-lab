// ============================================================================
// Client VM — Simulates AWS-side SQL Server connecting over VPN
// ============================================================================

param location string
param clientSubnetId string
param adminUsername string
@secure()
param adminPasswordOrKey string

@allowed(['password', 'sshPublicKey'])
param authenticationType string = 'password'

param vmSize string = 'Standard_B1s'

// ---- cloud-init: install netcat for testing ----
var cloudInitScript = '''#cloud-config
package_update: true
packages:
  - netcat-openbsd
'''

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

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-vm-client'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-vm-client'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: clientSubnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-client'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'vm-client'
      adminUsername: adminUsername
      adminPassword: authenticationType == 'password' ? adminPasswordOrKey : null
      linuxConfiguration: linuxConfiguration
      customData: base64(cloudInitScript)
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
          id: nic.id
        }
      ]
    }
  }
}

// ---- Outputs ----
output vmName string = vm.name
output publicIp string = pip.properties.ipAddress
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
