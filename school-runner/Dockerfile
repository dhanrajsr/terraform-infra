FROM myoung34/github-runner:ubuntu-jammy

# ── versions ────────────────────────────────────────────────────────────────
ARG JAVA_VERSION=21
ARG MAVEN_VERSION=3.9.9
ARG NODE_VERSION=20

# ── system packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      unzip \
      git \
      jq \
      ca-certificates \
      gnupg \
      lsb-release \
      apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ───────────────────────────────────────────────────────────────
RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "aarch64" ]; then AWS_ARCH="aarch64"; else AWS_ARCH="x86_64"; fi \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install --update \
    && rm -rf /tmp/aws /tmp/awscli.zip

# ── Java (Temurin via apt) ───────────────────────────────────────────────────
RUN curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] \
       https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-${JAVA_VERSION}-jdk \
    && rm -rf /var/lib/apt/lists/*

# ── Maven ────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      | tar -xz -C /opt \
    && ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn

# ── Node.js (via NodeSource) ─────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Verify installs ──────────────────────────────────────────────────────────
RUN aws --version \
    && java -version \
    && mvn -version \
    && node --version \
    && npm --version \
    && jq --version
