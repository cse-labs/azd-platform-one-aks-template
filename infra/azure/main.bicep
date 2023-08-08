targetScope = 'subscription'

@description('ID of the principal')
param principalId string = ''

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unqiue hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@minLength(1)
@description('Github Personal Access Token')
param githubToken string

@minLength(1)
@description('Ironbank Container Registry Credential Username')
param ironbankUsername string

@minLength(1)
@secure()
@description('Ironbank Container Registry Credential Password')
param ironbankPassword string

@minLength(1)
@description('GitOps Repository owner/repository name')
param gitopsRepo string

@minLength(1)
@description('GitOps Repository release branch name being continuously monitored by the agent')
param gitopsReleaseBranch string = 'main'

@minLength(3)
@description('Kubernetes Version')
param kubernetesVersion string

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var aksTags = {'gitops-repo': gitopsRepo, 'gitops-release-branch': gitopsReleaseBranch}

param enableMonitoring bool = true

param kube object = {
  version: kubernetesVersion
  nodeSize: 'Standard_D4ls_v5'
  nodeCount: 6
  nodeCountMax: 10
}

// Resource group to hold all resources
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'azd-${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module network 'modules/network.bicep' = {
  scope: resourceGroup
  name: 'network'
  params: {
    location: location
    subnetName: '${abbrs.networkVirtualNetworksSubnets}${environmentName}'
    name:  '${abbrs.networkVirtualNetworks}${environmentName}'
  }
}

module other 'modules/monitoring.bicep' = if(enableMonitoring) {
  scope: resourceGroup
  name: 'monitors'
  params: {
    location: location
    name: '${abbrs.monitor}${environmentName}'
  }
}

module kv 'modules/keyvault.bicep' = {
  scope: resourceGroup
  name: 'kv'
  params: {
    location: location
    principalId: principalId
    kvName: '${abbrs.keyVaultVaults}${resourceToken}'
  }
}

module keyVaultSecrets 'modules/keyvault-secrets.bicep' = {
  scope: resourceGroup
  name: 'keyvault-secrets'
  params: {
    keyVaultName: kv.outputs.name
    tags: tags
    secrets: [
      {
        name: 'githubToken'
        value: githubToken
      }
      {
        name: 'ironbankUsername'
        value: ironbankUsername
      }
      {
        name: 'ironbankPassword'
        value: ironbankPassword
      }
    ]
  }
}

module aks 'modules/aks.bicep' = {
  scope: resourceGroup
  name: 'aks'
  params: {
    location: location
    tags: union(aksTags, tags)
    name: '${abbrs.containerServiceManagedClusters}${resourceToken}'
    // Base AKS config like version and nodes sizes
    kube: kube

    // Network details
    netVnet: network.outputs.vnetName
    netSubnet: network.outputs.aksSubnetName

    // Optional features
    logsWorkspaceId: enableMonitoring ? other.outputs.id : ''
  }
}

// The Azure Container Registry to hold the images
module acr 'modules/acr.bicep' = {
  name: 'container-registry'
  scope: resourceGroup
  params: {
    location: location
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    tags: tags
  }
}

// Grant ACR Pull access from cluster managed identity to container registry
module containerRegistryAccess 'modules/aks-acr-role-assignment.bicep' = {
  name: 'cluster-container-registry-access'
  scope: resourceGroup
  params: {
    aksPrincipalId: aks.outputs.clusterIdentity.objectId
    acrName: acr.outputs.name
    desc: 'AKS cluster managed identity'
  }
}

output AZURE_AKS_CLUSTER_NAME string = aks.outputs.clusterName
output AZURE_AKS_CLUSTERIDENTITY_OBJECT_ID string = aks.outputs.clusterIdentity.objectId
output AZURE_AKS_CLUSTERIDENTITY_CLIENT_ID string = aks.outputs.clusterIdentity.clientId
output AZURE_RESOURCE_GROUP string = resourceGroup.name
output clusterFQDN string = aks.outputs.clusterFQDN
output aksState string = aks.outputs.provisioningState
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_KEY_VAULT_ENDPOINT string = kv.outputs.endpoint
output AZURE_KEY_VAULT_NAME string = kv.outputs.name
output AZURE_KEY_VAULT_RESOURCE_GROUP string = kv.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_CONTAINER_REGISTRY_RESOURCE_GROUP string = resourceGroup.name
output GITOPS_REPO_RELEASE_BRANCH string = gitopsReleaseBranch
