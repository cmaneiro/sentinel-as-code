<#
.SYNOPSIS
Validates and deploys Microsoft Sentinel scheduled analytic rules.

.DESCRIPTION
Reads rule definitions from the rules folder and deploys them to one Microsoft
Sentinel workspace through the Azure Resource Manager REST API. Dry-run mode
performs all local validation without authenticating to Azure.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkspaceName,

    [string]$RulesPath = (Join-Path $PSScriptRoot 'rules'),

    [string]$ApiVersion = '2024-03-01',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$validSeverities = @('High', 'Medium', 'Low', 'Informational')

if (-not (Test-Path -LiteralPath $RulesPath -PathType Container)) {
    throw "Rules directory not found: $RulesPath"
}

$ruleFiles = @(Get-ChildItem -LiteralPath $RulesPath -Filter '*.json' -File | Sort-Object Name)
if ($ruleFiles.Count -eq 0) {
    throw "No analytic rule JSON files found in: $RulesPath"
}

$accessToken = $null
if (-not $DryRun) {
    $accessToken = az account get-access-token `
        --subscription $SubscriptionId `
        --resource 'https://management.azure.com/' `
        --query accessToken `
        --output tsv

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
        throw "Azure authentication failed. Run 'az login' for the target tenant and subscription."
    }
}

$deployedCount = 0
foreach ($ruleFile in $ruleFiles) {
    $rule = Get-Content -LiteralPath $ruleFile.FullName -Raw | ConvertFrom-Json -Depth 20

    $ruleId = [guid]::Empty
    if (-not [guid]::TryParse($rule.id, [ref]$ruleId)) {
        throw "$($ruleFile.Name): 'id' must be a GUID."
    }
    if ($rule.kind -ne 'Scheduled') {
        throw "$($ruleFile.Name): only Scheduled analytic rules are supported."
    }
    if ([string]::IsNullOrWhiteSpace($rule.properties.displayName)) {
        throw "$($ruleFile.Name): properties.displayName is required."
    }
    if ([string]::IsNullOrWhiteSpace($rule.properties.query)) {
        throw "$($ruleFile.Name): properties.query is required."
    }
    if ($rule.properties.severity -notin $validSeverities) {
        throw "$($ruleFile.Name): invalid severity '$($rule.properties.severity)'."
    }
    if ($rule.properties.enabled -isnot [bool]) {
        throw "$($ruleFile.Name): properties.enabled must be true or false."
    }

    [void][System.Xml.XmlConvert]::ToTimeSpan($rule.properties.queryFrequency)
    [void][System.Xml.XmlConvert]::ToTimeSpan($rule.properties.queryPeriod)

    $payload = @{
        kind       = $rule.kind
        properties = $rule.properties
    } | ConvertTo-Json -Depth 20

    Write-Host "Validated: $($rule.properties.displayName) [$ruleId]" -ForegroundColor Green
    if ($DryRun) {
        Write-Host "Dry run: no Azure changes were made." -ForegroundColor Yellow
        continue
    }

    $encodedResourceGroup = [uri]::EscapeDataString($ResourceGroupName)
    $encodedWorkspace = [uri]::EscapeDataString($WorkspaceName)
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$encodedResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$encodedWorkspace/providers/Microsoft.SecurityInsights/alertRules/${ruleId}?api-version=$ApiVersion"
    $headers = @{
        Authorization = "Bearer $accessToken"
    }

    $response = Invoke-RestMethod `
        -Method Put `
        -Uri $uri `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $payload

    if ($response.name -ne $ruleId.ToString()) {
        throw "$($ruleFile.Name): Azure returned unexpected rule id '$($response.name)'."
    }

    $deployedCount++
    Write-Host "Deployed: $($rule.properties.displayName)" -ForegroundColor Cyan
}

Write-Host "Validated $($ruleFiles.Count) rule(s). Deployed $deployedCount rule(s)." -ForegroundColor Cyan
