# Compliance Report

This report maps the current repository controls to CIS Microsoft Azure
Foundations Benchmark v2.0.0 and supporting DevSecOps evidence. It is a
design-time compliance report, not a live attestation. Live compliance must be
confirmed after deploying to Azure and reviewing Defender for Cloud, Azure
Policy, and Sentinel evidence.

## Report Metadata

| Field | Value |
|---|---|
| Project | Azure DevSecOps + Zero Trust Lab |
| Report date | 2026-06-04 |
| Benchmark | CIS Microsoft Azure Foundations Benchmark v2.0.0 |
| Azure scope | Subscription-level lab deployment, pending live Azure deployment |
| Environments | `dev`, `prod` parameter sets |
| Evidence sources | Bicep, Azure Policy JSON/Bicep, GitHub Actions, Azure DevOps pipeline, KQL, workbook, demo app tests |
| Current assessment type | Source review and local validation |

## Important Note

Microsoft states that Azure Policy compliance mappings are a partial view of
overall compliance and do not guarantee full compliance with every CIS
requirement. This report follows the same model: it records source evidence,
expected Azure evidence, and gaps to validate after deployment.

## Status Definitions

| Status | Meaning |
|---|---|
| Implemented as code | Control is represented in source and has passed local syntax/security validation. |
| Ready to enable | Control exists but is disabled by default due to cost, tenant permissions, or rollout safety. |
| Partial | Control is partly addressed but needs more services, live evidence, or operational process. |
| Pending Azure validation | Control cannot be confirmed until deployed and assessed in Azure. |
| Out of scope | Control is not part of the current lab boundary. |

## Evidence Summary

| Area | Evidence | Current Result |
|---|---|---|
| Secrets scanning | Gitleaks in CI and local scan | No leaks found in latest local validation. |
| SAST | Semgrep OWASP and secrets rules | 0 blocking findings in latest local validation. |
| Container scanning | Trivy image/filesystem scan in CI | Pipeline target exists; local filesystem scan passed. |
| IaC scanning | Checkov for Bicep | CI gate implemented; Defender Standard findings are documented lab exceptions. |
| Defender for DevOps | MSDO GitHub Action and Azure DevOps task | CI gate implemented. |
| Bicep validation | `az bicep build`, `az bicep build-params` | Previously validated for infra/policy dev/prod parameters. |
| Application tests | Python unit tests | 7 tests passed in latest local validation. |
| KQL content | Sentinel detection files | Required header and output fields present. |

## Accepted Lab Exceptions

| Tool / Control | Exception | Rationale | Revisit Trigger |
|---|---|---|---|
| Checkov `CKV_AZURE_19` | Defender Standard pricing is not enforced by default. | Defender Standard can create Azure cost, so the lab defines plans as code but keeps `enableDefenderPlans = false`. | Budget approval and production promotion. |
| Checkov `CKV_AZURE_84` | Defender for Storage is not enabled by default. | No storage workload is deployed yet, and Defender for Storage can incur cost. | Storage module deployment and budget approval. |
| Checkov `CKV_AZURE_87` | Defender for Key Vault is not enabled by default. | Key Vault resources are not deployed yet, and Defender for Key Vault can incur cost. | Key Vault module deployment and budget approval. |

## CIS Azure Benchmark Mapping

| CIS Control | Requirement | Repository Evidence | Status | Gap / Next Step |
|---|---|---|---|---|
| 1.23 | Ensure that no custom subscription administrator roles exist | Templates avoid creating custom admin roles or broad Owner/Contributor assignments. Policy remediation uses Tag Contributor only. | Partial | Validate actual Azure subscription RBAC after deployment. |
| 2.1.1 | Ensure that Microsoft Defender for Servers is set to On | `infra/parameters/prod.bicepparam` includes `VirtualMachines` Defender plan with `P2`, guarded by `enableDefenderPlans`. | Ready to enable | Enable after cost review and confirm Defender for Cloud regulatory compliance. |
| 2.1.10 | Ensure that Microsoft Defender for Key Vault is set to On | `infra/parameters/prod.bicepparam` includes `KeyVaults` Defender plan, guarded by `enableDefenderPlans`. | Ready to enable | Enable after cost review and deploy Key Vault resources. Checkov exception `CKV_AZURE_87` tracks this tradeoff. |
| 3.1 | Ensure that Secure transfer required is set to Enabled | `policy/definitions/require-https.json` checks `Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly`. | Implemented as code | Deploy policy assignment and validate compliance results. |
| 3.10 | Ensure Private Endpoints are used to access Storage Accounts | `infra/modules/network.bicep` creates a private endpoint subnet; policy report documents private connectivity intent. | Partial | Add storage account and private endpoint module when storage is introduced. |
| 5.4 | Ensure resource logs are enabled for Azure services | `infra/modules/sentinel.bicep` creates Log Analytics and Sentinel; KQL playbook lists required tables. | Partial | Add diagnostic settings for each deployed Azure resource. |
| 9.2 | Ensure web app redirects all HTTP traffic to HTTPS in Azure App Service | `policy/definitions/require-https.json` checks `Microsoft.Web/sites/httpsOnly`; app also emits secure headers. | Implemented as code | Validate when App Service or container hosting is added. |
| Supporting control | Reduce public network exposure | `policy/definitions/deny-public-ip.json` audits/denies `Microsoft.Network/publicIPAddresses`; NSGs default-deny inbound. | Implemented as code | Validate with Azure Policy compliance after deployment. |
| Supporting control | Enforce required governance tags | `policy/definitions/enforce-tags.json` supports audit/modify with remediation tasks and Tag Contributor. | Implemented as code | Run remediation only after reviewing tag values. |
| Supporting control | Require CI security gates before deployment | `.github/workflows/ci-security.yml` and `pipeline/azure-devops/azure-pipelines.yml` include Gitleaks, Semgrep, Trivy, Checkov, and MSDO. | Implemented as code | Enforce branch protection in GitHub settings. |
| Supporting control | Monitor privilege escalation and secret access | `sentinel/detection-rules/*.kql` and `sentinel/workbooks/security-posture.json`. | Implemented as code | Import analytics rules into Sentinel and tune thresholds. |
| Supporting control | Avoid long-lived Azure deployment secrets | `.github/workflows/cd-azure.yml` uses `azure/login@v2` with OIDC permissions. | Ready to enable | Create federated credential and repository/environment secrets. |

## Policy Enforcement Profile

| Environment | Public IP | HTTPS | Tags | Assignment Enforcement |
|---|---|---|---|---|
| `dev` | `audit` | `audit` | `audit` | `DoNotEnforce` |
| `prod` | `deny` | `deny` | `modify` | `Default` |

## Open Compliance Gaps

| Gap | Reason | Planned Action |
|---|---|---|
| No live Defender for Cloud compliance score | Dev is deployed, but Defender Standard plans remain disabled by design. | Export Defender for Cloud regulatory compliance evidence and enable paid plans only after budget review. |
| Conditional Access not enabled | Requires Graph permissions and break-glass object IDs. | Test report-only policy state before enforcement. |
| No diagnostic settings for workload resources yet | Demo app has not been hosted in Azure. | Add diagnostic settings module when App Service, Container Apps, or AKS is chosen. |
| Storage private endpoint not implemented | No storage account exists in the lab scope yet. | Add storage module with private endpoint when app needs persistent storage. |
| KQL not tested on real data | No Log Analytics workspace data yet. | Connect Entra ID, Azure Activity, and Key Vault diagnostics, then run rule tests. |

## Recommended Evidence Collection After Deployment

1. Export Azure Policy compliance for the custom `azzt-cis-*` initiative.
2. Export Defender for Cloud regulatory compliance assessment for CIS v2.0.0.
3. Capture GitHub Actions run URL for the five passing CI security checks.
4. Save `az deployment sub what-if` output for infra and policy changes.
5. Record Sentinel analytics rule test results and workbook screenshots.
6. Capture Azure Activity events for policy assignment and remediation creation.

## References

- Microsoft Learn: Regulatory Compliance details for CIS Microsoft Azure Foundations Benchmark 2.0.0, https://learn.microsoft.com/en-us/azure/governance/policy/samples/cis-azure-2-0-0
- Microsoft Learn: Azure Policy Regulatory Compliance controls for Azure Storage, https://learn.microsoft.com/en-us/azure/storage/common/security-controls-policy
- Microsoft Learn: Azure Policy Regulatory Compliance controls for Azure App Service, https://learn.microsoft.com/en-us/azure/app-service/security-controls-policy
