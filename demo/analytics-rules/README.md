# Microsoft Sentinel content deployment from GitHub

This demo deploys one generic scheduled analytic rule to one Microsoft Sentinel
workspace. It demonstrates source control, pull request validation, GitHub
Actions, OpenID Connect (OIDC), and repeatable content deployment.

The repository contains no customer tenant, subscription, or workspace
identifiers. The deployment target is configured with GitHub environment
variables.

## Demo flow

1. Edit or add a rule under `rules/`.
2. Open a pull request and show the `Validate content` job.
3. Merge the validated change.
4. Open **Actions > Deploy Sentinel content > Run workflow**.
5. Run with `dry_run=true` to preview.
6. Run with `dry_run=false` to deploy.
7. Open Microsoft Sentinel and show the rule under **Analytics**.

The sample rule is disabled by default so that deploying the demo does not
create operational alerts. Enable it only after reviewing the query and target
workspace.

## Repository structure

```text
.github/workflows/deploy-sentinel-content.yml
demo/analytics-rules/
  Deploy-SentinelAnalyticsRules.ps1
  README.md
  rules/
    azure-resource-deletion.json
```

## GitHub environment configuration

Create an environment named `gnb-demo` and add these environment variables:

| Variable | Purpose |
|---|---|
| `AZURE_CLIENT_ID` | Application client ID used by GitHub OIDC |
| `AZURE_TENANT_ID` | Tenant containing the Sentinel workspace |
| `AZURE_SUBSCRIPTION_ID` | Subscription containing the workspace |
| `SENTINEL_RESOURCE_GROUP` | Resource group containing the workspace |
| `SENTINEL_WORKSPACE_NAME` | Log Analytics workspace with Sentinel enabled |

These values are identifiers, not credentials. Do not create or store a client
secret.

## Azure OIDC configuration

Create an Entra application and service principal, then add a federated
credential with:

```text
Issuer:   https://token.actions.githubusercontent.com
Subject:  repo:cmaneiro/sentinel-as-code:environment:gnb-demo
Audience: api://AzureADTokenExchange
```

Grant the service principal **Microsoft Sentinel Contributor** on the target
workspace or its resource group. Keep the scope as narrow as the demo permits.

## Local validation

PowerShell 7 is required:

```powershell
./Deploy-SentinelAnalyticsRules.ps1 `
  -SubscriptionId "00000000-0000-0000-0000-000000000000" `
  -ResourceGroupName "demo-resource-group" `
  -WorkspaceName "demo-workspace" `
  -DryRun
```

For a local deployment, first sign in to the target Azure tenant with Azure
CLI, select the correct subscription, and run the same command without
`-DryRun`.

## Adding another analytic rule

Copy the sample JSON file and change:

- `id`: use a new GUID
- `displayName` and `description`
- KQL query
- severity, tactics, and techniques
- scheduling and entity mappings

The deployment uses the rule GUID as the Azure resource name. Re-running the
workflow updates the same rule instead of creating a duplicate.
