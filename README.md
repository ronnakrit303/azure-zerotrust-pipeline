# Azure DevSecOps + Zero Trust Lab

Enterprise-grade DevSecOps pipeline on Azure with CI/CD security automation,
Zero Trust architecture, and compliance-as-code.

## Architecture

```mermaid
graph TB
    subgraph CI_CD[CI/CD Pipeline]
        A[GitHub Push] --> B[Gitleaks and Semgrep]
        B --> C[Trivy and Checkov]
        C --> D[Defender for DevOps]
        D --> E[Deploy via OIDC]
    end

    subgraph Azure[Azure Zero Trust]
        E --> F[Bicep IaC Deploy]
        F --> G[VNet and NSG Microsegmentation]
        G --> H[Demo App]
    end

    subgraph Identity[Identity]
        I[Entra ID] --> J[Conditional Access MFA]
        J --> H
    end

    subgraph Monitoring[Monitoring]
        H --> K[Log Analytics Workspace]
        K --> L[Microsoft Sentinel]
        L --> M[KQL Detection Rules]
    end

    subgraph Compliance[Compliance]
        F --> N[Azure Policy]
        N --> O[CIS Benchmark Report]
    end
```

## Quick Start

```bash
# TODO: Login to Azure.
az login

# TODO: Bootstrap environment.
bash scripts/setup-azure.sh

# TODO: Deploy infrastructure when Bicep modules are implemented.
az deployment sub create \
  --location southeastasia \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam

# TODO: Run local security scans.
bash scripts/run-scans.sh
```

## Project Status

This repository currently contains the starter scaffold only. Implementation
logic, Azure resources, CI/CD gates, policies, and KQL queries should be added
module by module.

