FROM myoung34/github-runner:ubuntu-jammy

# ── versions (update here to upgrade) ──────────────────────────────────────
ARG TERRAFORM_VERSION=1.10.5
ARG KUBECTL_VERSION=1.32.0
ARG HELM_VERSION=3.17.1
ARG ARGOCD_VERSION=2.14.4

# ── system packages ─────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      unzip \
      git \
      jq \
      python3 \
      python3-pip \
      python3-venv \
      ca-certificates \
      gnupg \
      lsb-release \
      apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ───────────────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

# ── Azure CLI ────────────────────────────────────────────────────────────────
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
       https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends azure-cli \
    && rm -rf /var/lib/apt/lists/*

# ── Google Cloud CLI ─────────────────────────────────────────────────────────
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
       https://packages.cloud.google.com/apt cloud-sdk main" \
       > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# ── Terraform ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
      -o /tmp/terraform.zip \
    && unzip -q /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && chmod +x /usr/local/bin/terraform

# ── kubectl ──────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# ── Helm ─────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | \
      tar -xz --strip-components=1 -C /usr/local/bin linux-amd64/helm \
    && chmod +x /usr/local/bin/helm

# ── ArgoCD CLI ───────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" \
      -o /usr/local/bin/argocd \
    && chmod +x /usr/local/bin/argocd

# ── Verify installs ──────────────────────────────────────────────────────────
RUN aws --version \
    && az version \
    && gcloud version \
    && terraform version \
    && kubectl version --client \
    && helm version \
    && argocd version --client \
    && python3 --version \
    && jq --version
