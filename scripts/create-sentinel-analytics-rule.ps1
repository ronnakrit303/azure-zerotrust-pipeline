param(
    [string]$ResourceGroupName = "rg-devsecops-dev-sea",
    [string]$WorkspaceName = "log-devsecops-dev-sea",
    [string]$RuleId = "8b5f7d4f-4d0f-4a18-97f0-6df1d55b72e8",
    [string]$QueryPath = "sentinel\detection-rules\secrets-exfiltration.kql",
    [string]$ApiVersion = "2025-09-01"
)

$ErrorActionPreference = "Stop"
$env:AZURE_CORE_COLLECT_TELEMETRY = "0"

if (-not (Test-Path -Path $QueryPath)) {
    throw "KQL query file not found: $QueryPath"
}

$subscriptionId = az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw "Azure subscription ID was not returned by az account show."
}

$scheduledRule = @{
    kind = "Scheduled"
    properties = @{
        displayName = "AZZT - Key Vault Secrets Exfiltration Monitor (dev)"
        description = "Detects high-volume Key Vault secret, key, and certificate reads/list/backup operations. Lab validated with Key Vault AuditEvent telemetry."
        severity = "High"
        enabled = $true
        query = Get-Content -Path $QueryPath -Raw
        queryFrequency = "PT15M"
        queryPeriod = "P1D"
        triggerOperator = "GreaterThan"
        triggerThreshold = 0
        suppressionDuration = "PT1H"
        suppressionEnabled = $false
        tactics = @(
            "CredentialAccess"
        )
        techniques = @(
            "T1552"
        )
        entityMappings = @(
            @{
                entityType = "Account"
                fieldMappings = @(
                    @{
                        identifier = "Name"
                        columnName = "AccountName"
                    }
                )
            },
            @{
                entityType = "IP"
                fieldMappings = @(
                    @{
                        identifier = "Address"
                        columnName = "IPAddress"
                    }
                )
            }
        )
        customDetails = @{
            Action = "Action"
            DetectionSeverity = "Severity"
            OperationCount = "OperationCount"
            VaultCount = "VaultCount"
            FirstSeen = "FirstSeen"
            LastSeen = "LastSeen"
        }
        eventGroupingSettings = @{
            aggregationKind = "SingleAlert"
        }
        incidentConfiguration = @{
            createIncident = $true
            groupingConfiguration = @{
                enabled = $true
                reopenClosedIncident = $false
                lookbackDuration = "PT1H"
                matchingMethod = "Selected"
                groupByEntities = @(
                    "Account",
                    "IP"
                )
                groupByAlertDetails = @()
                groupByCustomDetails = @()
            }
        }
    }
}

$tempRule = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "azzt-sentinel-scheduled-rule.json"
$url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/alertRules/$RuleId`?api-version=$ApiVersion"

try {
    $scheduledRule | ConvertTo-Json -Depth 30 | Set-Content -Path $tempRule -Encoding utf8

    az rest `
        --method put `
        --url $url `
        --headers Content-Type=application/json `
        --body "@$tempRule" `
        --query "{name:name,displayName:properties.displayName,kind:kind,enabled:properties.enabled,severity:properties.severity,frequency:properties.queryFrequency,period:properties.queryPeriod,createIncident:properties.incidentConfiguration.createIncident}" `
        -o table
}
finally {
    if (Test-Path -Path $tempRule) {
        Remove-Item -Path $tempRule -Force
    }
}
