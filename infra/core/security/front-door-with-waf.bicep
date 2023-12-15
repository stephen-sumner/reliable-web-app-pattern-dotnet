// =====================================================================================================================
//     USER-DEFINED TYPES
// =====================================================================================================================

// From: infra/types/DiagnosticSettings.bicep
@description('The diagnostic settings for a resource')
type DiagnosticSettings = {
  @description('The number of days to retain log data.')
  logRetentionInDays: int

  @description('The number of days to retain metric data.')
  metricRetentionInDays: int

  @description('If true, enable diagnostic logging.')
  enableLogs: bool

  @description('If true, enable metrics logging.')
  enableMetrics: bool
}

type WAFRuleSet = {
  @description('The name of the rule set')
  name: string

  @description('The version of the rule set')
  version: string
}

// =====================================================================================================================
//     PARAMETERS
// =====================================================================================================================

@description('The diagnostic settings to use for this resource')
param diagnosticSettings DiagnosticSettings

@description('The tags to associate with the resource')
param tags object

/*
** Resource names to create
*/
@description('The name of the Azure Front Door endpoint to create')
param frontDoorEndpointName string

@description('The name of the Azure Front Door profile to create')
param frontDoorProfileName string

@description('The name of the Web Application Firewall to create')
param webApplicationFirewallName string

/*
** Dependencies
*/
@description('The Log Analytics Workspace to send diagnostic and audit data to')
param logAnalyticsWorkspaceId string

/*
** Service settings
*/
@description('A list of managed rule sets to enable')
param managedRules WAFRuleSet[]

@allowed([ 'Premium', 'Standard' ])
@description('The pricing plan to use for the Azure Front Door and Web Application Firewall')
param sku string

// =====================================================================================================================
//     CALCULATED VARIABLES
// =====================================================================================================================

// For a list of all categories that this resource supports, see: https://learn.microsoft.com/azure/azure-monitor/essentials/resource-logs-categories
var logCategories = [
  'FrontDoorAccessLog'
  'FrontDoorWebApplicationFirewallLog'
] 

// Convert the managed rule sets list into the object form required by the web application firewall
var managedRuleSets = map(managedRules, rule => {
  ruleSetType: rule.name
  ruleSetVersion: rule.version
  ruleSetAction: 'Block'
  ruleGroupOverrides: []
  exclusions: []
})

// =====================================================================================================================
//     AZURE RESOURCES
// =====================================================================================================================

resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: frontDoorProfileName
  location: 'global'
  tags: tags
  sku: {
    name: '${sku}_AzureFrontDoor'
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  name: frontDoorEndpointName
  parent: frontDoorProfile
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: webApplicationFirewallName
  location: 'global'
  tags: tags
  sku: {
    name: '${sku}_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    customRules: {
      rules: []
    }
    managedRules: {
      managedRuleSets: sku == 'Premium' ? managedRuleSets : []
    }
  }
}

resource wafPolicyLink 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  name: '${webApplicationFirewallName}-link'
  parent: frontDoorProfile
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            { id: frontDoorEndpoint.id }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticSettings != null && !empty(logAnalyticsWorkspaceId)) {
  name: '${frontDoorProfileName}-diagnostics'
  scope: frontDoorProfile
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: map(logCategories, (category) => {
      category: category
      enabled: diagnosticSettings!.enableLogs
    })
    metrics: [
      {
        category: 'AllMetrics'
        enabled: diagnosticSettings!.enableMetrics
      }
    ]
  }
}

// =====================================================================================================================
//     AZURE RESOURCES
// =====================================================================================================================

output endpoint_name string = frontDoorEndpoint.name
output profile_name string = frontDoorProfile.name
output waf_name string = wafPolicy.name

output front_door_id string = frontDoorProfile.properties.frontDoorId
output hostname string = frontDoorEndpoint.properties.hostName
output uri string = 'https://${frontDoorEndpoint.properties.hostName}'
