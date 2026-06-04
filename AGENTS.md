# AGENTS.md - Azure DevSecOps + Zero Trust Lab

## Project Overview
A portfolio project demonstrating enterprise-grade DevSecOps on Azure,
combining CI/CD security automation, Zero Trust architecture, and
compliance-as-code.

Target audience: Microsoft internship / DevSecOps roles.

Author: ReVerse (Ronnakrit Woralakpakdee)

Stack: Azure DevOps, GitHub Actions, Bicep, Entra ID, Defender for DevOps,
Microsoft Sentinel, KQL.

## Repository Structure

```text
azure-zerotrust-pipeline/
|-- AGENTS.md
|-- README.md
|-- docs/
|   |-- architecture.md
|   |-- threat-model.md
|   |-- compliance-report.md
|   `-- kql-playbook.md
|-- infra/
|   |-- main.bicep
|   |-- modules/
|   |   |-- network.bicep
|   |   |-- identity.bicep
|   |   |-- defender.bicep
|   |   `-- sentinel.bicep
|   `-- parameters/
|       |-- dev.bicepparam
|       `-- prod.bicepparam
|-- pipeline/
|   |-- .github/
|   |   `-- workflows/
|   |       |-- ci-security.yml
|   |       `-- cd-azure.yml
|   `-- azure-devops/
|       `-- azure-pipelines.yml
|-- policy/
|   |-- definitions/
|   |   |-- deny-public-ip.json
|   |   |-- require-https.json
|   |   `-- enforce-tags.json
|   |-- assignments/
|   |   `-- cis-benchmark.json
|   `-- remediation/
|       `-- auto-remediate.ps1
|-- app/
|   |-- Dockerfile
|   |-- src/
|   `-- tests/
|-- sentinel/
|   |-- detection-rules/
|   |   |-- lateral-movement.kql
|   |   |-- privilege-escalation.kql
|   |   `-- secrets-exfiltration.kql
|   `-- workbooks/
|       `-- security-posture.json
`-- scripts/
    |-- setup-azure.sh
    |-- run-scans.sh
    `-- export-compliance.ps1
```

## Agent Instructions

### General Rules
- All Bicep templates must pass `az bicep build` without errors before committing.
- All KQL queries must be tested against real Log Analytics workspace data.
- Never hardcode secrets, keys, or connection strings. Use Azure Key Vault references.
- Follow Microsoft naming conventions: `<type>-<workload>-<env>-<region>`.
- Every infrastructure change must have a corresponding entry in `docs/architecture.md`.

### CI/CD Pipeline Tasks
When modifying `pipeline/` files, ensure the following security gates are present:

1. Secrets scanning - Gitleaks.
2. SAST - Semgrep with OWASP Top Ten and secrets rulesets.
3. Container scanning - Trivy.
4. IaC scanning - Checkov for Bicep/ARM templates.
5. Defender for DevOps - Microsoft Security DevOps GitHub Action.

Pipeline should fail fast: secrets scan runs first, and builds proceed only if clean.

### Bicep / Infrastructure Tasks
- Use `@description()` on every parameter and resource.
- Storage accounts must disable public blob access and require TLS 1.2 or newer.
- VMs and containers should send logs to the Log Analytics workspace in Sentinel.
- NSG rules should default-deny inbound traffic.
- Assign least-privilege RBAC. Avoid subscription-scope Owner or Contributor.

### Zero Trust Tasks
- Enforce MFA through Conditional Access.
- Block legacy authentication protocols.
- Apply Entra ID PIM for privileged roles.
- Document identity policy decisions in `docs/architecture.md`.

### Azure Policy Tasks
- Each policy JSON must include `metadata.version` and `metadata.category`.
- Map policies to CIS Azure Benchmark controls.
- Test policies in `audit` mode before switching to `deny`.
- Add remediation tasks for `deployIfNotExists` policies.

### KQL / Sentinel Tasks
- Include a comment header: `// Tactic: <MITRE tactic> | Technique: <T-ID>`.
- Document each rule in `docs/kql-playbook.md`.
- Queries should return `TimeGenerated`, `AccountName`, `IPAddress`, `Action`, and `Severity`.

### Documentation Tasks
- `threat-model.md` uses STRIDE format.
- `compliance-report.md` maps findings to CIS Azure Benchmark v2.0 controls.
- Architecture diagrams should use Mermaid syntax in Markdown code blocks.

