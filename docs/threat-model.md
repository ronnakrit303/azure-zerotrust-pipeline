# Threat Model

This STRIDE threat model covers the demo API, CI/CD workflows, Azure deployment
path, policy controls, and Sentinel detection surface for the
azure-zerotrust-pipeline lab.

## Scope

In scope:

- Developer workflow from local changes to GitHub.
- GitHub Actions and Azure DevOps pipeline definitions.
- Demo API under `app/`, including Docker build and runtime behavior.
- Azure Bicep templates under `infra/`.
- Azure Policy definitions, assignment, and remediation under `policy/`.
- Sentinel KQL rules and workbook under `sentinel/`.

Out of scope for the current phase:

- Live Azure tenant configuration that has not been deployed yet.
- Production hosting platform hardening beyond the demo container.
- Full identity governance reviews such as access reviews and PIM assignment reviews.
- Third-party SaaS dependencies outside GitHub, Azure, and container registries.

## Assets

| Asset | Security Objective |
|---|---|
| Source code | Prevent tampering, secret leaks, and insecure changes. |
| GitHub Actions OIDC trust | Prevent unauthorized Azure deployments. |
| Azure subscription | Prevent broad public exposure and privileged misuse. |
| Demo API | Provide a safe target for scan, build, and runtime validation. |
| Log Analytics and Sentinel | Preserve detection evidence and investigation context. |
| Policy assignment identity | Remediate only intended tag drift. |

## Assumptions

- The repository is public, so no sensitive values are committed.
- GitHub repository settings can enforce required checks before merge.
- Azure deployment credentials are provided through OIDC federation, not static secrets.
- Conditional Access is tested in report-only mode before enforcement.
- Sentinel rules are tuned against real workspace data before production use.

## STRIDE Analysis

| Category | Threat | Impact | Mitigation | Status |
|---|---|---|---|---|
| Spoofing | Attacker opens a pull request that appears to be normal application work but attempts to alter deployment behavior. | Unauthorized infrastructure change or weakened policy controls. | Required CI security checks, code review, path-specific workflow visibility, no direct secret use in workflow shell commands. | Implemented as code, repository rule enforcement pending. |
| Spoofing | GitHub workflow attempts Azure login without a valid trusted OIDC subject. | Failed deployment or unauthorized trust if federation is misconfigured. | `azure/login@v2` with OIDC, environment-specific secrets, no client secret. | Ready for Azure setup. |
| Spoofing | Attacker impersonates a valid API caller by sending forged event payloads. | False telemetry or misleading security event routing. | Demo API accepts only known event types and severities; production auth is future work. | Partial, demo only. |
| Tampering | Malicious change weakens Bicep, policy, or KQL files. | Security controls drift from intended baseline. | Gitleaks, Semgrep, Checkov, Trivy, MSDO, reviewable policy-as-code and docs. | Implemented. |
| Tampering | Container image is modified after tests pass. | Runtime differs from reviewed source. | Dockerfile runs unit tests during build stage and copies only source into runtime stage. | Implemented. |
| Tampering | Azure Policy remediation modifies unintended resource fields. | Governance automation causes resource drift. | Remediation limited to tag `addOrReplace`, Tag Contributor role, opt-in `tagEffect == modify`. | Implemented as code. |
| Repudiation | Operator denies making a privileged deployment or policy assignment. | Poor incident reconstruction. | GitHub run logs, Azure deployment names include run number, Azure Activity logs, Sentinel workbook and KQL playbook. | Implemented as design, pending Azure logs. |
| Repudiation | API events cannot be correlated to requests. | Triage and replay analysis are difficult. | Demo API emits JSON logs with request ID, method, path, status, service, and environment. | Implemented. |
| Information Disclosure | Secrets are committed to the public repo. | Credential compromise. | `.gitignore`, Gitleaks, Semgrep secrets rules, no hardcoded secret values. | Implemented. |
| Information Disclosure | Public IP or HTTP-only service exposes workload over the internet. | Data exposure and interception risk. | Custom Azure Policy denies public IPs and requires HTTPS for supported services; network module avoids public inbound by default. | Implemented as code. |
| Information Disclosure | Demo API leaks platform details through headers. | Reconnaissance information disclosure. | Security headers and custom server version string. | Implemented. |
| Denial of Service | Large request body exhausts demo API memory. | API instability. | `APP_MAX_BODY_BYTES` guard and request size validation. | Implemented. |
| Denial of Service | Azure Policy deny effects block expected deployments before validation. | Delivery interruption. | Dev policy parameters use audit and `DoNotEnforce`; prod enforcement is explicit. | Implemented. |
| Denial of Service | Sentinel query costs grow due to broad query windows. | Slow investigations and high ingestion/query cost. | KQL rules use bounded lookback, windowed summarization, and documented thresholds. | Implemented, pending tuning. |
| Elevation of Privilege | Pipeline service principal gains broad Azure role. | Full subscription compromise. | OIDC is preferred, and templates avoid subscription-scope Owner/Contributor. | Design implemented, Azure role assignment pending. |
| Elevation of Privilege | Conditional Access deployment script receives excessive Graph permissions. | Tenant-wide identity control abuse. | Deployment is disabled by default and requires break-glass exclusions before use. | Partial, requires tenant setup. |
| Elevation of Privilege | Privileged role assignment or app consent goes unnoticed. | Persistent tenant compromise. | Sentinel privilege escalation KQL detects role, owner, PIM, and consent operations. | Implemented as KQL, pending live validation. |

## Key Abuse Cases

| Abuse Case | Preventive Control | Detective Control |
|---|---|---|
| Commit a token into source | `.gitignore`, Gitleaks, Semgrep secrets | CI failure and SARIF/code scanning alert. |
| Add public IP to workload | Azure Policy `deny-public-ip`, network design | Policy compliance result and Azure Activity. |
| Disable HTTPS on supported service | Azure Policy `require-https` | Policy compliance result. |
| Add Global Administrator to compromised account | Least privilege review, Conditional Access | `privilege-escalation.kql`. |
| Password spray followed by valid sign-in | MFA Conditional Access | `lateral-movement.kql`. |
| Bulk read Key Vault secrets | Key Vault RBAC and Defender for Key Vault | `secrets-exfiltration.kql`. |

## Residual Risk

| Risk | Reason | Recommended Follow-up |
|---|---|---|
| No live Azure validation yet | The lab has not been deployed in this environment. | Deploy `dev`, run what-if, and collect Policy/Sentinel evidence. |
| Demo API has no production authentication | It is a scan target, not a production API. | Add auth middleware when a real hosting target is selected. |
| Conditional Access automation requires Graph permissions | Bicep cannot directly create these policies without Graph automation. | Grant the managed identity only the documented Graph application permissions and test report-only. |
| Compliance coverage is partial | CIS Azure includes many tenant and service controls outside this lab. | Expand controls after deployment and run Defender for Cloud regulatory compliance assessment. |

## Validation Backlog

- Deploy `infra/main.bicep` to a dev subscription.
- Run `az deployment sub what-if` for both infra and policy templates.
- Enable Entra sign-in and audit log connectors in Log Analytics.
- Import Sentinel analytics rules and workbook.
- Generate test events for sign-in failures, role assignment, and Key Vault read/list activity.
- Confirm GitHub branch protection requires the five CI security checks.
