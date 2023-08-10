@description('Custom tags to apply to the resources')
param tags object = {}

param name string
param location string
param applicationInsightsName string
param applicationInsightsDashboardName string

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2020-08-01' = {
  location: location
  name: name
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

module applicationInsights './applicationinsights.bicep' = {
  name: 'applicationinsights'
  params: {
    name: applicationInsightsName
    location: location
    tags: tags
    dashboardName: applicationInsightsDashboardName
    logAnalyticsWorkspaceId: logWorkspace.id
  }
}

output id string = logWorkspace.id
output name string = logWorkspace.name
output connectionString string = applicationInsights.outputs.connectionString
output instrumentationKey string = applicationInsights.outputs.instrumentationKey
output appInsightsName string = applicationInsights.name
