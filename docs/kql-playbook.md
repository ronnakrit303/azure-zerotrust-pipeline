# KQL Playbook

This playbook documents the Microsoft Sentinel detections in `sentinel/detection-rules/`.
Each rule returns the common triage fields `TimeGenerated`, `AccountName`, `IPAddress`,
`Action`, and `Severity` so the results can be mapped into Sentinel entities and custom
details later.

## Data Sources

| Table | Purpose | Required connector |
|---|---|---|
| `SigninLogs` | Identity sign-in behavior and password-spray patterns | Microsoft Entra ID |
| `AuditLogs` | Role management, PIM activation, consent, and ownership changes | Microsoft Entra ID |
| `AzureDiagnostics` | Key Vault diagnostic audit events | Azure Key Vault diagnostic settings |
| `AzureActivity` | Control-plane Key Vault operations | Azure Activity |
| `SecurityAlert` | Workbook posture summary | Microsoft Sentinel |

> Note: The rules are written to use common Sentinel tables, but they still need to be
> tuned and tested against a real Log Analytics workspace before production enforcement.

## Detection Rule Index

| Rule | MITRE Tactic | Technique | Status |
|---|---|---|---|
| Lateral Movement Detection | Lateral Movement | T1021 | Implemented |
| Privilege Escalation Alert | Privilege Escalation | T1098 | Implemented |
| Secrets Exfiltration Monitor | Exfiltration | T1552 | Implemented |

## Rules

### Lateral Movement Detection

- File: `sentinel/detection-rules/lateral-movement.kql`
- What it detects: multiple failed Entra ID sign-ins against distinct accounts followed by a successful sign-in from the same IP within a short window.
- Why it matters: this is a useful cloud identity signal for password spray, credential stuffing, or movement through reused credentials.
- Recommended schedule: run every 15 minutes with a 1 day lookback.
- Default tuning: `FailedSignInThreshold = 8`, `DistinctAccountThreshold = 3`, `Window = 15m`.
- Expected entities: map `AccountName` to Account and `IPAddress` to IP.
- False positive scenarios: shared NAT, VPN concentrators, identity testing, helpdesk password reset waves, or developer test tenants.
- Investigation steps: review the successful account, source IP reputation, sign-in location, conditional access result, MFA result, user agent, and whether failures targeted unrelated users.
- Response guidance: revoke user sessions, require password reset, block the IP at Conditional Access or firewall layer, and verify no new OAuth grants or privileged role changes followed.

### Privilege Escalation Alert

- File: `sentinel/detection-rules/privilege-escalation.kql`
- What it detects: privileged role assignments, eligible role assignments, PIM activations, app role grants, delegated permission grants, admin consent, and owner changes on applications or service principals.
- Why it matters: unauthorized privilege changes are a direct path to tenant compromise and persistence.
- Recommended schedule: run every 15 minutes with a 1 day lookback.
- Default tuning: operations are controlled by the `PrivilegedRoleOperations` dynamic array.
- Expected entities: map `AccountName` to Account and `IPAddress` to IP. Use `CorrelationId` for audit trace correlation.
- False positive scenarios: planned admin onboarding, break-glass testing, application deployment pipelines, and approved PIM activation windows.
- Investigation steps: confirm change approval, inspect the target resource and role, validate the initiating account or app, review nearby sign-ins, and check whether the same actor changed Conditional Access, app credentials, or Key Vault access.
- Response guidance: remove unauthorized role or grant, disable affected credentials, rotate app secrets/certificates, and preserve the audit event correlation ID.

### Secrets Exfiltration Monitor

- File: `sentinel/detection-rules/secrets-exfiltration.kql`
- What it detects: high-volume Key Vault secret, key, or certificate read/list activity and backup operations from the same account and IP.
- Why it matters: secret reads and backups can expose credentials used by infrastructure, applications, and pipelines.
- Recommended schedule: run every 15 minutes with a 1 day lookback.
- Default tuning: `SecretOperationThreshold = 20`, `VaultThreshold = 2`, `Window = 15m`.
- Expected entities: map `AccountName` to Account and `IPAddress` to IP.
- False positive scenarios: backup jobs, deployment pipelines, certificate renewal automation, vault inventory scripts, or incident response collection.
- Investigation steps: identify the vaults touched, compare the account to approved automation, inspect operation mix, check source IP, review recent role assignment changes, and confirm whether any secrets were rotated afterward.
- Response guidance: disable or restrict the offending identity, rotate affected secrets, review Key Vault access policies/RBAC, and create an allowlist only for approved automation identities.

## Workbook

The workbook artifact is `sentinel/workbooks/security-posture.json`. It includes:

- Time range parameter for interactive triage.
- Detection coverage table for the three custom rules.
- Sentinel alert volume by severity.
- Lateral movement candidates from `SigninLogs`.
- Privileged role and consent changes from `AuditLogs`.
- Key Vault access anomalies from `AzureDiagnostics` and `AzureActivity`.
