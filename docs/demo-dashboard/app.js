const evidenceItems = [
  {
    title: "CI Security workflow",
    category: "GitHub Actions",
    description: "Security gates passed across secrets, SAST, container, IaC, and MSDO checks.",
    image: "../portfolio/assets/github-ci-security-success.png",
  },
  {
    title: "CD Azure what-if",
    category: "GitHub Actions",
    description: "OIDC login and Bicep what-if completed for the dev environment.",
    image: "../portfolio/assets/github-cd-azure-what-if-success.png",
  },
  {
    title: "Azure resource group",
    category: "Azure",
    description: "Dev resource group includes Log Analytics, Sentinel solution, VNet, and NSGs.",
    image: "../portfolio/assets/azure-rg-devsecops-dev-sea-resources.png",
  },
  {
    title: "Policy assignment detail",
    category: "Governance",
    description: "Custom baseline assigned in dev with policy enforcement set to DoNotEnforce.",
    image: "../portfolio/assets/azure-policy-assignment-azzt-cis-dev-sea-detail.png",
  },
  {
    title: "Sentinel overview",
    category: "Sentinel",
    description: "Microsoft Sentinel is onboarded to the Log Analytics workspace.",
    image: "../portfolio/assets/azure-sentinel-overview.png",
  },
  {
    title: "Azure Activity ingestion",
    category: "Telemetry",
    description: "AzureActivity rows confirm subscription activity is flowing into Log Analytics.",
    image: "../portfolio/assets/azure-activity-log-ingestion.png",
  },
  {
    title: "Key Vault AuditEvent ingestion",
    category: "KQL",
    description: "AzureDiagnostics received Key Vault AuditEvent rows with SecretGet and SecretList.",
    image: "../portfolio/assets/azure-keyvault-auditevent-ingestion.png",
  },
  {
    title: "Secrets exfiltration detection",
    category: "KQL",
    description: "The KQL rule generated a High severity detection from controlled test telemetry.",
    image: "../portfolio/assets/kql-secrets-exfiltration-detection.png",
  },
  {
    title: "Compliance export summary",
    category: "Compliance",
    description: "Compliance evidence export produced passing local, Azure, Bicep, and what-if checks.",
    image: "../portfolio/assets/compliance-export-summary.png",
  },
];

const grid = document.querySelector("#evidenceGrid");
const search = document.querySelector("#evidenceSearch");
const dialog = document.querySelector("#evidenceDialog");
const dialogTitle = document.querySelector("#dialogTitle");
const dialogCategory = document.querySelector("#dialogCategory");
const dialogImage = document.querySelector("#dialogImage");
const closeDialog = document.querySelector("#closeDialog");

function renderEvidence() {
  const fragment = document.createDocumentFragment();
  evidenceItems.forEach((item) => {
    const article = document.createElement("article");
    article.className = "evidence-card";
    article.dataset.search = `${item.title} ${item.category} ${item.description}`.toLowerCase();

    const previewButton = document.createElement("button");
    previewButton.type = "button";
    previewButton.setAttribute("aria-label", `Preview ${item.title}`);

    const image = document.createElement("img");
    image.src = item.image;
    image.alt = item.title;
    image.loading = "lazy";
    previewButton.append(image);

    const copy = document.createElement("div");
    copy.className = "evidence-copy";
    copy.innerHTML = `
      <span class="badge info">${item.category}</span>
      <h4>${item.title}</h4>
      <p>${item.description}</p>
    `;

    previewButton.addEventListener("click", () => {
      dialogTitle.textContent = item.title;
      dialogCategory.textContent = item.category;
      dialogImage.src = item.image;
      dialogImage.alt = item.title;
      dialog.showModal();
    });

    article.append(previewButton, copy);
    fragment.append(article);
  });
  grid.append(fragment);
}

function filterEvidence() {
  const term = search.value.trim().toLowerCase();
  document.querySelectorAll(".evidence-card").forEach((card) => {
    card.hidden = term.length > 0 && !card.dataset.search.includes(term);
  });
}

function filterLanes(laneName) {
  document.querySelectorAll(".segment").forEach((button) => {
    button.classList.toggle("active", button.dataset.lane === laneName);
  });

  document.querySelectorAll(".lane").forEach((lane) => {
    lane.hidden = laneName !== "all" && lane.dataset.lane !== laneName;
  });
}

document.querySelectorAll(".segment").forEach((button) => {
  button.addEventListener("click", () => filterLanes(button.dataset.lane));
});

document.querySelectorAll(".nav-item").forEach((item) => {
  item.addEventListener("click", () => {
    document.querySelectorAll(".nav-item").forEach((navItem) => navItem.classList.remove("active"));
    item.classList.add("active");
  });
});

search.addEventListener("input", filterEvidence);

closeDialog.addEventListener("click", () => {
  dialog.close();
});

dialog.addEventListener("click", (event) => {
  if (event.target === dialog) {
    dialog.close();
  }
});

renderEvidence();
