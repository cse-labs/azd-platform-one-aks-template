param name string
param location string

@description('Custom tags to apply to the resources')
param tags object = {}

param netVnet string
param netSubnet string
param principalId string
param logsWorkspaceId string = ''

param kube object = {
  nodeSize: 'Standard_DS2_v2'
  nodeCount: 1
  nodeCountMin: 5
  nodeCountMax: 10
}

var addOns = {
  azurepolicy: {
    enabled: true
  }
  azureKeyvaultSecretsProvider: {
    config: {
      enableSecretRotation: 'false'
    }
    enabled: true
  }
   // Enable monitoring add on, only if logsWorkspaceId is set
  omsagent: logsWorkspaceId != '' ? {
    enabled: true
    config: {
      logAnalyticsWorkspaceResourceID: logsWorkspaceId
    }
  }: {}
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
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: subscription().tenantId
    }
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

resource adminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, 'aks-admin-${principalId}')
  scope: aks
  properties: {
    // Azure Kubernetes Service Cluster Admin Role
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
    principalId: principalId
  }
}
resource userRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, 'aks-user-${principalId}')
  scope: aks
  properties: {
    // Azure Kubernetes Service Cluster User Role
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f')
    principalId: principalId
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

@description('The Keyvault Provider Worker cluster identity')
output keyvaultProviderIdentity object = {
  clientId: aks.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.clientId
  objectId: aks.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
  resourceId: aks.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.resourceId
}
