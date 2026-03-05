@description('Azure region for all resources')
param location string

@description('Tags for all resources')
param tags object

@description('Unique token for resource naming')
param resourceToken string

@description('Container image for canvas service')
param canvasImageName string

@description('Container image for MCP service')
param mcpImageName string

@secure()
@description('API key for MCP SSE authentication')
param mcpApiKey string

var abbrs = loadJsonContent('../abbreviations.json')

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: '${abbrs.containerRegistryRegistries}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
  }
}

// User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
  location: location
  tags: tags
}

// AcrPull role assignment for managed identity
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentity.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: containerRegistry
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${abbrs.appManagedEnvironments}${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Canvas Container App (internal ingress — only MCP can reach it)
resource canvasApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${abbrs.appContainerApps}canvas-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'canvas' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
        }
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'canvas'
          image: !empty(canvasImageName) ? '${containerRegistry.properties.loginServer}/${canvasImageName}' : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            { name: 'NODE_ENV', value: 'production' }
            { name: 'PORT', value: '3000' }
            { name: 'HOST', value: '0.0.0.0' }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
  dependsOn: [
    acrPullRole
  ]
}

// MCP Container App (external ingress with API key auth)
resource mcpApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${abbrs.appContainerApps}mcp-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'mcp' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3001
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
        }
      }
      secrets: [
        {
          name: 'mcp-api-key'
          value: mcpApiKey
        }
      ]
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp'
          image: !empty(mcpImageName) ? '${containerRegistry.properties.loginServer}/${mcpImageName}' : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            { name: 'NODE_ENV', value: 'production' }
            { name: 'MCP_TRANSPORT', value: 'sse' }
            { name: 'MCP_PORT', value: '3001' }
            { name: 'EXPRESS_SERVER_URL', value: 'https://${canvasApp.properties.configuration.ingress.fqdn}' }
            { name: 'ENABLE_CANVAS_SYNC', value: 'true' }
            { name: 'EXCALIDRAW_EXPORT_DIR', value: '/tmp' }
            { name: 'MCP_API_KEY', secretRef: 'mcp-api-key' }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
  dependsOn: [
    acrPullRole
  ]
}

output containerRegistryEndpoint string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
output canvasUri string = 'https://${canvasApp.properties.configuration.ingress.fqdn}'
output mcpUri string = 'https://${mcpApp.properties.configuration.ingress.fqdn}'
