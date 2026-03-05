targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g., dev, staging, prod)')
param environmentName string

@minLength(1)
@description('Primary Azure region for all resources')
param location string

@description('Name of the resource group')
param resourceGroupName string = ''

@description('Container image for the canvas service')
param canvasImageName string = ''

@description('Container image for the MCP service')
param mcpImageName string = ''

@secure()
@description('API key for MCP SSE endpoint authentication')
param mcpApiKey string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var tags = { 'azd-env-name': environmentName }
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module app './app/app.bicep' = {
  name: 'app'
  scope: rg
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    canvasImageName: canvasImageName
    mcpImageName: mcpImageName
    mcpApiKey: mcpApiKey
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = app.outputs.containerRegistryEndpoint
output AZURE_CONTAINER_REGISTRY_NAME string = app.outputs.containerRegistryName
output AZURE_RESOURCE_GROUP string = rg.name
output SERVICE_CANVAS_URI string = app.outputs.canvasUri
output SERVICE_MCP_URI string = app.outputs.mcpUri
