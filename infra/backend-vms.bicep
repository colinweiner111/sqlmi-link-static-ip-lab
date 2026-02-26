// ============================================================================
// Backend VMs — Simulate SQL MI endpoints (vm-sql-a + vm-sql-b)
// ============================================================================

param location string
param backendSubnetId string
param adminUsername string
@secure()
param adminPasswordOrKey string

@allowed(['password', 'sshPublicKey'])
param authenticationType string = 'password'

param vmSize string = 'Standard_B1s'

// ---- cloud-init: install socat and start a TCP 5022 listener ----
var cloudInitScript = '''#cloud-config
package_update: true
packages:
  - socat
write_files:
  - path: /etc/systemd/system/socat-listener.service
    content: |
      [Unit]
      Description=Socat TCP 5022 Listener (simulates SQL MI)
      After=network.target

      [Service]
      ExecStart=/bin/bash -c 'while true; do echo "Connected to $(hostname)" | socat - TCP-LISTEN:5022,reuseaddr; done'
      Restart=always
      RestartSec=1

      [Install]
      WantedBy=multi-user.target
runcmd:
  - systemctl daemon-reload
  - systemctl enable socat-listener
  - systemctl start socat-listener
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

// ---- VM A (10.0.2.4) ----
resource nicA 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-vm-sql-a'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.2.4'
          subnet: {
            id: backendSubnetId
          }
        }
      }
    ]
  }
}

resource vmA 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-sql-a'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'vm-sql-a'
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
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicA.id
        }
      ]
    }
  }
}

// ---- VM B (10.0.2.5) ----
resource nicB 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-vm-sql-b'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.2.5'
          subnet: {
            id: backendSubnetId
          }
        }
      }
    ]
  }
}

resource vmB 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-sql-b'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'vm-sql-b'
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
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicB.id
        }
      ]
    }
  }
}

// ---- Outputs ----
output vmAName string = vmA.name
output vmAPrivateIp string = nicA.properties.ipConfigurations[0].properties.privateIPAddress
output vmBName string = vmB.name
output vmBPrivateIp string = nicB.properties.ipConfigurations[0].properties.privateIPAddress
