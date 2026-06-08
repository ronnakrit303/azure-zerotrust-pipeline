# Export local and Azure compliance evidence for the Zero Trust lab.

[CmdletBinding()]
param(
    [ValidateSet("dev", "prod")]
    [string]$Environment = "dev",

    [string]$Location = "southeastasia",

    [string]$OutputDirectory = "reports/compliance",

    [switch]$SkipAzure,

    [switch]$RunWhatIf,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$GeneratedAtUtc = (Get-Date).ToUniversalTime()
$Timestamp = $GeneratedAtUtc.ToString("yyyyMMddTHHmmssZ")
$RunDirectory = Join-Path $OutputDirectory "$Environment-$Timestamp"
$Results = New-Object System.Collections.Generic.List[object]

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Write-WarningLine {
    param([string]$Message)
    Write-Warning $Message
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Convert-ToRelativePath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetFullPath($RepoRoot.Path)
    $relative = $fullPath.Substring($rootPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return ($relative -replace "\\", "/")
}

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$File,
        [string]$Notes = ""
    )

    $Results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        file = $File
        notes = $Notes
    }) | Out-Null
}

function Invoke-EvidenceCommand {
    param(
        [string]$Name,
        [scriptblock]$Command,
        [string]$FileName,
        [switch]$AllowFailure
    )

    Write-Step $Name

    $outputPath = Join-Path $RunDirectory $FileName
    $global:LASTEXITCODE = 0
    $exitCode = 0
    $outputText = ""

    try {
        $output = & $Command 2>&1
        if ($null -ne $global:LASTEXITCODE) {
            $exitCode = [int]$global:LASTEXITCODE
        }
        $outputText = ($output | Out-String).TrimEnd()
    }
    catch {
        $exitCode = 1
        $outputText = ($_ | Out-String).TrimEnd()
    }

    if ([string]::IsNullOrWhiteSpace($outputText)) {
        $outputText = "(no output)"
    }

    Set-Content -Path $outputPath -Value $outputText -Encoding utf8

    if ($exitCode -eq 0) {
        Add-Result -Name $Name -Status "pass" -File $FileName
        return
    }

    $note = "exit code $exitCode"
    if ($AllowFailure) {
        Add-Result -Name $Name -Status "warning" -File $FileName -Notes $note
        Write-WarningLine "$Name completed with $note"
        return
    }

    Add-Result -Name $Name -Status "fail" -File $FileName -Notes $note
    throw "$Name failed with $note. See $outputPath"
}

function Write-JsonFile {
    param(
        [string]$FileName,
        [object]$Value
    )

    $path = Join-Path $RunDirectory $FileName
    $Value | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding utf8
}

function Export-SourceInventory {
    Write-Step "Source file inventory"

    $excludedParts = @(".git", ".venv", "venv", "node_modules", "reports", "__pycache__")
    $extensions = @(".bicep", ".bicepparam", ".json", ".kql", ".md", ".ps1", ".sh", ".yml", ".yaml")

    $files = Get-ChildItem -Path . -Recurse -File |
        Where-Object {
            $parts = $_.FullName.Substring($RepoRoot.Path.Length).Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            -not ($parts | Where-Object { $excludedParts -contains $_ }) -and
            ($extensions -contains $_.Extension.ToLowerInvariant())
        } |
        Sort-Object FullName |
        ForEach-Object {
            $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
            [pscustomobject]@{
                path = Convert-ToRelativePath -Path $_.FullName
                bytes = $_.Length
                sha256 = $hash.Hash.ToLowerInvariant()
            }
        }

    Write-JsonFile -FileName "source-file-inventory.json" -Value $files
    Add-Result -Name "Source file inventory" -Status "pass" -File "source-file-inventory.json" -Notes "$($files.Count) files"
}

function Export-LocalEvidence {
    Write-Step "Local metadata"

    $metadata = [ordered]@{
        project = "azure-zerotrust-pipeline"
        environment = $Environment
        location = $Location
        generatedAtUtc = $GeneratedAtUtc.ToString("o")
        repoRoot = $RepoRoot.Path
    }

    Write-JsonFile -FileName "metadata.json" -Value $metadata
    Add-Result -Name "Export metadata" -Status "pass" -File "metadata.json"

    if (Test-Path "docs/compliance-report.md") {
        Copy-Item -Path "docs/compliance-report.md" -Destination (Join-Path $RunDirectory "compliance-report-source.md") -Force
        Add-Result -Name "CIS compliance report source" -Status "pass" -File "compliance-report-source.md"
    }

    if (Test-CommandExists "git") {
        Invoke-EvidenceCommand -Name "Git branch" -FileName "git-branch.txt" -Command { git rev-parse --abbrev-ref HEAD } -AllowFailure
        Invoke-EvidenceCommand -Name "Git commit" -FileName "git-commit.txt" -Command { git rev-parse HEAD } -AllowFailure
        Invoke-EvidenceCommand -Name "Git working tree status" -FileName "git-status.txt" -Command { git status --short } -AllowFailure
    }
    else {
        Add-Result -Name "Git metadata" -Status "warning" -File "" -Notes "git not installed"
    }

    Export-SourceInventory

    if (Test-CommandExists "az") {
        Invoke-EvidenceCommand -Name "Azure Bicep version" -FileName "az-bicep-version.txt" -Command { az bicep version } -AllowFailure

        $infraOut = Join-Path $RunDirectory "infra-main.json"
        $policyOut = Join-Path $RunDirectory "policy-main.json"

        Invoke-EvidenceCommand -Name "Build infra Bicep" -FileName "bicep-build-infra.log" -Command { az bicep build --file "infra/main.bicep" --outfile $infraOut }
        Invoke-EvidenceCommand -Name "Build policy Bicep" -FileName "bicep-build-policy.log" -Command { az bicep build --file "policy/main.bicep" --outfile $policyOut }
        Invoke-EvidenceCommand -Name "Build infra parameters" -FileName "infra-parameters.json" -Command { az bicep build-params --file "infra/parameters/$Environment.bicepparam" --stdout }
        Invoke-EvidenceCommand -Name "Build policy parameters" -FileName "policy-parameters.json" -Command { az bicep build-params --file "policy/parameters/$Environment.bicepparam" --stdout }
    }
    else {
        Add-Result -Name "Bicep evidence" -Status "warning" -File "" -Notes "az CLI not installed"
    }
}

function Test-AzureLogin {
    if ($SkipAzure) {
        Add-Result -Name "Azure evidence" -Status "warning" -File "" -Notes "skipped by -SkipAzure"
        return $false
    }

    if (-not (Test-CommandExists "az")) {
        Add-Result -Name "Azure evidence" -Status "warning" -File "" -Notes "az CLI not installed"
        return $false
    }

    $global:LASTEXITCODE = 0
    $null = az account show -o none 2>$null
    if ($global:LASTEXITCODE -ne 0) {
        Add-Result -Name "Azure evidence" -Status "warning" -File "" -Notes "az login required"
        Write-WarningLine "Azure CLI is not logged in. Run az login or use -SkipAzure for local-only exports."
        return $false
    }

    return $true
}

function Export-AzureEvidence {
    Write-Step "Azure evidence"

    Invoke-EvidenceCommand -Name "Azure account" -FileName "azure-account.json" -Command { az account show -o json }
    Invoke-EvidenceCommand -Name "Azure Policy assignments" -FileName "azure-policy-assignments.json" -Command { az policy assignment list -o json } -AllowFailure
    Invoke-EvidenceCommand -Name "Azure Policy compliance summary" -FileName "azure-policy-state-summary.json" -Command { az policy state summarize -o json } -AllowFailure
    Invoke-EvidenceCommand -Name "Defender pricing plans" -FileName "azure-defender-pricing.json" -Command { az security pricing list -o json } -AllowFailure
    Invoke-EvidenceCommand -Name "Log Analytics workspaces" -FileName "azure-log-analytics-workspaces.json" -Command { az monitor log-analytics workspace list -o json } -AllowFailure

    if ($RunWhatIf) {
        Invoke-EvidenceCommand -Name "Infra deployment what-if" -FileName "azure-what-if-infra.txt" -Command {
            az deployment sub what-if --location $Location --template-file "infra/main.bicep" --parameters "infra/parameters/$Environment.bicepparam"
        } -AllowFailure

        Invoke-EvidenceCommand -Name "Policy deployment what-if" -FileName "azure-what-if-policy.txt" -Command {
            az deployment sub what-if --location $Location --template-file "policy/main.bicep" --parameters "policy/parameters/$Environment.bicepparam"
        } -AllowFailure
    }
}

function Write-Summary {
    $summaryPath = Join-Path $RunDirectory "summary.md"
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("# Compliance Evidence Export") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- Project: azure-zerotrust-pipeline") | Out-Null
    $lines.Add("- Environment: $Environment") | Out-Null
    $lines.Add("- Location: $Location") | Out-Null
    $lines.Add("- Generated at UTC: $($GeneratedAtUtc.ToString("o"))") | Out-Null
    $lines.Add("- Output directory: $RunDirectory") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("## Evidence") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Check | Status | File | Notes |") | Out-Null
    $lines.Add("|---|---|---|---|") | Out-Null

    foreach ($result in $Results) {
        $file = if ([string]::IsNullOrWhiteSpace($result.file)) { "" } else { $result.file }
        $notes = if ([string]::IsNullOrWhiteSpace($result.notes)) { "" } else { $result.notes }
        $lines.Add("| $($result.name) | $($result.status) | $file | $notes |") | Out-Null
    }

    $lines.Add("") | Out-Null
    $lines.Add("## Handling Notes") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- Evidence files can include subscription IDs, tenant IDs, resource names, and policy state.") | Out-Null
    $lines.Add("- Keep generated reports out of Git unless they are intentionally sanitized.") | Out-Null
    $lines.Add('- `reports/` is ignored by `.gitignore` for this reason.') | Out-Null

    Set-Content -Path $summaryPath -Value $lines -Encoding utf8
}

if ((Test-Path $RunDirectory) -and -not $Force) {
    throw "Output directory already exists: $RunDirectory. Use -Force to overwrite."
}

New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null

Export-LocalEvidence

if (Test-AzureLogin) {
    Export-AzureEvidence
}

Write-Summary

Write-Host ""
Write-Host "Compliance evidence exported to: $RunDirectory"
Write-Host "Summary: $(Join-Path $RunDirectory "summary.md")"
