param name string
param location string

@description('Custom tags to apply to the resources')
param tags object = {}

param netVnet string
param netSubnet string
param logsWorkspaceId string = ''

param kube object = {
  nodeSize: 'Standard_DS2_v2'
  nodeCount: 1
  nodeCountMin: 5
  nodeCountMax: 10
}

@description('This is the built-in Azure Kubernetes Service RBAC Cluster Admin role. See https://docs.microsoft.com/azure/role-based-access-control/built-in-roles#azure-kubernetes-service-rbac-cluster-admin')
resource aksRbacClusterAdminRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
}

var addOns = {
  azurepolicy: {
    enabled: true
  }
  // Enable monitoring add on, only if logsWorkspaceId is set
  omsagent: logsWorkspaceId != '' ? {
    enabled: true
    config: {
      logAnalyticsWorkspaceResourceID: logsWorkspaceId
    }
  } : {}
}

resource aks 'Microsoft.ContainerService/managedClusters@2020-12-01' = {
  name: name
  location: location

  identity: {
    type: 'SystemAssigned'
  }
  tags: union(tags, {'control-plane-type': 'K8'})

  properties: {
    dnsPrefix: name
    kubernetesVersion: kube.version
    enableRBAC: true

    agentPoolProfiles: [
      {
        name: 'default'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', netVnet, netSubnet)
        vmSize: kube.nodeSize
        enableAutoScaling: true
        count: kube.nodeCount
        minCount: kube.nodeCount
        maxCount: kube.nodeCountMax

        // Must enable CustomNodeConfigPreview
        // https://docs.microsoft.com/en-us/azure/aks/custom-node-configuration#register-the-customnodeconfigpreview-preview-feature
        linuxOSConfig: {
          sysctls: {
            vmMaxMapCount: 262144
          }
        }
      }
    ]

    // Enable advanced networking and policy
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
    }

    // Add ons are configured above, as a conditional variable object
    addonProfiles: addOns
  }
}

output clusterName string = aks.name
output clusterFQDN string = aks.properties.fqdn
output provisioningState string = aks.properties.provisioningState

@description('The AKS cluster identity')
output clusterIdentity object = {
  clientId: aks.properties.identityProfile.kubeletidentity.clientId
  objectId: aks.properties.identityProfile.kubeletidentity.objectId
  resourceId: aks.properties.identityProfile.kubeletidentity.resourceId
}
