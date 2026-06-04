<#
.SYNOPSIS
Creates Azure Policy remediation tasks for tag enforcement references.

.DESCRIPTION
Use this after the baseline initiative is assigned with tagEffect=modify and
the assignment managed identity has the Tag Contributor role at the assignment
scope. The script is intentionally scoped to tag modify remediation because the
public IP and HTTPS policies are audit/deny controls and do not remediate state.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [string]$LocationShort = 'sea',

    [string]$AssignmentName = '',

    [string[]]$PolicyDefinitionReferenceId = @(
        'enforce-tag-1',
        'enforce-tag-2',
        'enforce-tag-3',
        'enforce-tag-4'
    ),

    [ValidateSet('ExistingNonCompliant', 'ReEvaluateCompliance')]
    [string]$ResourceDiscoveryMode = 'ReEvaluateCompliance',

    [string[]]$LocationFilter = @()
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install Azure CLI and run az login before creating remediation tasks.'
}

if ([string]::IsNullOrWhiteSpace($AssignmentName)) {
    $AssignmentName = "azzt-cis-$Environment-$LocationShort"
}

$subscriptionId = az account show --query id --output tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'Azure CLI is not logged in or no subscription is selected.'
}

foreach ($referenceId in $PolicyDefinitionReferenceId) {
    $safeReferenceId = $referenceId -replace '[^a-zA-Z0-9-]', '-'
    $remediationName = "remediate-$AssignmentName-$safeReferenceId"
    $azArgs = @(
        'policy',
        'remediation',
        'create',
        '--name',
        $remediationName,
        '--policy-assignment',
        $AssignmentName,
        '--definition-reference-id',
        $referenceId,
        '--resource-discovery-mode',
        $ResourceDiscoveryMode
    )

    if ($LocationFilter.Count -gt 0) {
        $azArgs += '--location-filters'
        $azArgs += $LocationFilter
    }

    if ($PSCmdlet.ShouldProcess($referenceId, "Create remediation task $remediationName")) {
        az @azArgs
    }
}
