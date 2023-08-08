@description('Specifies the name of the key vault.')
param kvName string

@description('Specifies the Azure location where the key vault should be created.')
param location string = resourceGroup().location

@description('Specifies whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the key vault.')
param enabledForDeployment bool = false

@description('Specifies whether Azure Disk Encryption is permitted to retrieve secrets from the vault and unwrap keys.')
param enabledForDiskEncryption bool = false

@description('Specifies whether Azure Resource Manager is permitted to retrieve secrets from the key vault.')
param enabledForTemplateDeployment bool = false

@description('Specifies the permissions to keys in the vault. Valid values are: all, encrypt, decrypt, wrapKey, unwrapKey, sign, verify, get, list, create, update, import, delete, backup, restore, recover, and purge.')
param keysPermissions array = [
  'list', 'get', 'update', 'import'
]

@description('Specifies the permissions to secrets in the vault. Valid values are: all, get, list, set, delete, backup, restore, recover, and purge.')
param secretsPermissions array = [
  'list', 'get', 'set'
]

@description('Specifies the permissions to certs in the vault. Valid values are: all, get, list, set, delete, backup, restore, recover, and purge.')
param certificatePermissions array = [
  'list', 'get', 'import'
]

@description('Specifies whether the key vault is a standard vault or a premium vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'
param principalId string = ''
param policyName string = 'add'

resource kv 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: take(kvName, 23)
  location: location
  properties: {
    enabledForDeployment: enabledForDeployment
    tenantId: subscription().tenantId
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    accessPolicies: !empty(principalId) ? [
      {
        objectId: principalId
        permissions: {
          keys: keysPermissions
          secrets: secretsPermissions
          certificates: certificatePermissions
        }
        tenantId: subscription().tenantId
      }
    ] : []
    sku: {
      name: skuName
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource keyVaultAccessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  parent: kv
  name: policyName
  properties: {
    accessPolicies: [ {
        objectId: principalId
        tenantId: subscription().tenantId
        permissions: { secrets: secretsPermissions }
      } ]
  }
}

output endpoint string = kv.properties.vaultUri
output name string = kv.name
