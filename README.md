# School Management System — Phase 1 Deployment Guide

> **Phase 1**: Serverless deployment on AWS using Lambda + API Gateway + RDS PostgreSQL + CloudFront

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Repositories](#repositories)
4. [Infrastructure Components](#infrastructure-components)
5. [Self-Hosted GitHub Runners](#self-hosted-github-runners)
   - [First-Time Runner Setup](#first-time-runner-setup)
   - [Re-registering Runners](#re-registering-runners-after-token-expiry-or-corruption)
   - [Runner Management Reference](#runner-management-reference)
6. [Prerequisites](#prerequisites)
7. [Deployment Order](#deployment-order)
8. [Step 1 — Provision Infrastructure (Terraform)](#step-1--provision-infrastructure-terraform)
9. [Step 2 — Build & Upload Lambda JAR](#step-2--build--upload-lambda-jar)
10. [Step 3 — Deploy Frontend (school-ui)](#step-3--deploy-frontend-school-ui)
11. [Application Code — school-api-lambda](#application-code--school-api-lambda)
12. [API Reference](#api-reference)
13. [Custom Domain Setup](#custom-domain-setup)
14. [CI/CD Pipeline Reference](#cicd-pipeline-reference)
15. [Troubleshooting](#troubleshooting)

---

## Overview

Phase 1 deploys the School Management System as a fully serverless application on AWS.
No servers to manage — compute scales automatically, and you only pay per request.

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Frontend | React + Vite | Student/Branch/Course/Fees management UI |
| CDN | AWS CloudFront | Global content delivery, HTTPS, caching |
| Static Hosting | AWS S3 | Hosts built React assets |
| API Gateway | AWS HTTP API | Single entry point for all API requests |
| Backend | AWS Lambda (Java 21) | Spring Boot application running serverlessly |
| Database | AWS RDS PostgreSQL 16 | Persistent data store |
| State Storage | AWS S3 + DynamoDB | Terraform remote state and locking |

---

## Architecture

```
User Browser
     │
     ▼
┌─────────────────────────────────────┐
│  CloudFront (d15oeotzu3ugz0.cf.net) │  ← HTTPS, global CDN
│  Custom domain: school.devopscab.com│
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│         S3 Bucket (school-ui)       │  ← React static files (index.html, JS, CSS)
└─────────────────────────────────────┘

     │  (API calls via axios)
     ▼
┌─────────────────────────────────────┐
│  API Gateway HTTP API               │  ← Single $default catch-all route
│  cgaoh0ja3l.execute-api.us-east-1   │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  Lambda: school-api-dev             │  ← Java 21, 512MB, 30s timeout
│  Handler: StreamLambdaHandler       │  ← Cold start: ~10s, warm: ~50ms
│  Runtime: Spring Boot (fat JAR)     │
└──────────────────┬──────────────────┘
                   │  JDBC over internet (publicly accessible)
                   ▼
┌─────────────────────────────────────┐
│  RDS PostgreSQL 16 (school-dev)     │  ← db.t3.micro, 20GB gp2
│  Public subnet (EKS VPC)            │  ← HikariCP pool size: 2
└─────────────────────────────────────┘
```

### Why Lambda Instead of EKS/ECS?

| | Lambda (Phase 1) | EKS (Phase 2) |
|--|-----------------|---------------|
| Cost | Pay per request | Pay per node (always on) |
| Ops overhead | Zero | High (nodes, networking, upgrades) |
| Scaling | Automatic | Manual / HPA |
| Cold start | ~10s for Java | None |
| Best for | Learning, low traffic | Production, high traffic |

---

## Repositories

| Repository | Purpose | Runner |
|------------|---------|--------|
| `dhanrajsr/terraform-infra` | All Terraform infrastructure | `github-runner-terraform` |
| `dhanrajsr/school-api-lambda` | Spring Boot API converted for Lambda | `github-runner-school` |
| `dhanrajsr/school-ui` | React frontend | `github-runner-school` |
| `dhanrajsr/school-api` | Original Spring Boot API (for EKS/ECS — Phase 2) | — |

---

## Infrastructure Components

### Terraform Module: `modules/school-app`

Provisions the backend stack for one environment.

```
modules/school-app/
├── s3.tf          — S3 bucket for Lambda JAR uploads
├── rds.tf         — RDS PostgreSQL + subnet group + security group
├── lambda.tf      — IAM role, Lambda function, API Gateway permission
├── apigateway.tf  — HTTP API, Lambda integration, $default route, CloudWatch logs
├── variables.tf   — Input variables
└── outputs.tf     — api_gateway_url, rds_endpoint, lambda_function_name
```

**Key design decisions:**
- `payload_format_version = "1.0"` — required for `aws-serverless-java-container` (v2.0 format is incompatible)
- RDS placed in **public subnets** with `publicly_accessible = true` — Lambda runs outside the VPC so it needs a public endpoint. Restrict in production using VPC-attached Lambda.
- RDS subnet group uses EKS VPC public subnets (looked up by tag `eks-dev-us-east-1-vpc`)
- Lambda handler: `com.school.api.StreamLambdaHandler::handleRequest`

### Terraform Module: `modules/school-ui`

Provisions the frontend hosting stack.

```
modules/school-ui/
├── main.tf        — S3 bucket, CloudFront distribution, OAC, bucket policy
├── variables.tf   — environment, account_id, tags
└── outputs.tf     — cloudfront_url, s3_bucket, cloudfront_distribution_id
```

**Key design decisions:**
- S3 bucket is **private** — accessible only via CloudFront (Origin Access Control)
- CloudFront custom error responses: 403/404 → `index.html` (React Router SPA support)
- `index.html` deployed with `no-cache` header; JS/CSS assets with 1-year immutable cache
- `PriceClass_100` — US + Europe only (cheapest tier)

### Terraform Workspaces

Each service has its own Terraform workspace with separate state:

| Workspace | Path | State Key |
|-----------|------|-----------|
| EKS | `aws/us-east-1/dev/eks/` | `aws/us-east-1/dev/eks/terraform.tfstate` |
| School App | `aws/us-east-1/dev/school/` | `aws/us-east-1/dev/school/terraform.tfstate` |
| School UI | `aws/us-east-1/dev/school-ui/` | `aws/us-east-1/dev/school-ui/terraform.tfstate` |

State backend: S3 bucket `aws-terraform-state-497041484428` + DynamoDB table `terraform-state-lock`.

---

## Self-Hosted GitHub Runners

All CI/CD pipelines run on self-hosted Docker containers on your local Mac — not on GitHub-hosted runners.
This avoids GitHub Actions minute limits and allows the runners to access your local Docker environment.

### How It Works

```
GitHub Actions job triggers
         ↓
GitHub looks for a runner with matching labels (self-hosted, docker, linux)
         ↓
Docker container (running on your Mac) picks up the job
         ↓
Job runs inside the container using tools pre-installed in the image
         ↓
Results reported back to GitHub
```

### Runner Images

#### Terraform Runner (`dhanrajsubbaianind/github-runner-terraform`)

Used by: `terraform-infra`

| Tool | Version |
|------|---------|
| AWS CLI v2 | latest (arch-aware: amd64/arm64) |
| Azure CLI | latest |
| Google Cloud CLI | latest |
| Terraform | 1.10.5 |
| kubectl | 1.32.0 |
| Helm | 3.17.1 |
| ArgoCD CLI | 2.14.4 |

Build the image:
```
terraform-infra → Actions → Build Terraform Runner Image → Run workflow
```

#### School Runner (`dhanrajsubbaianind/github-runner-school`)

Used by: `school-api-lambda`, `school-ui`

| Tool | Version |
|------|---------|
| AWS CLI v2 | latest (arch-aware: amd64/arm64) |
| Java | 21 (Eclipse Temurin JDK) |
| Maven | 3.9.9 |
| Node.js | 20 |
| npm | bundled with Node.js |

Build the image:
```
terraform-infra → Actions → Build School Runner Image → Run workflow
```

---

### First-Time Runner Setup

Run these commands once to register and start all 3 runners.

#### Step 1 — Generate Registration Tokens

Tokens expire after 1 hour — generate them immediately before starting containers.

```bash
TOKEN_TERRAFORM=$(gh api --method POST \
  repos/dhanrajsr/terraform-infra/actions/runners/registration-token --jq '.token')

TOKEN_LAMBDA=$(gh api --method POST \
  repos/dhanrajsr/school-api-lambda/actions/runners/registration-token --jq '.token')

TOKEN_UI=$(gh api --method POST \
  repos/dhanrajsr/school-ui/actions/runners/registration-token --jq '.token')
```

#### Step 2 — Start Runner Containers

```bash
# Terraform runner
docker run -d --name runner-terraform --restart unless-stopped \
  -e REPO_URL=https://github.com/dhanrajsr/terraform-infra \
  -e RUNNER_TOKEN=$TOKEN_TERRAFORM \
  -e RUNNER_NAME=runner-terraform \
  -e LABELS=self-hosted,docker,linux \
  -e RUNNER_WORKDIR=/tmp/runner \
  dhanrajsubbaianind/github-runner-terraform:latest

# school-api-lambda runner
docker run -d --name runner-school-api-lambda --restart unless-stopped \
  -e REPO_URL=https://github.com/dhanrajsr/school-api-lambda \
  -e RUNNER_TOKEN=$TOKEN_LAMBDA \
  -e RUNNER_NAME=runner-school-api-lambda \
  -e LABELS=self-hosted,docker,linux \
  -e RUNNER_WORKDIR=/tmp/runner \
  dhanrajsubbaianind/github-runner-school:latest

# school-ui runner
docker run -d --name runner-school-ui --restart unless-stopped \
  -e REPO_URL=https://github.com/dhanrajsr/school-ui \
  -e RUNNER_TOKEN=$TOKEN_UI \
  -e RUNNER_NAME=runner-school-ui \
  -e LABELS=self-hosted,docker,linux \
  -e RUNNER_WORKDIR=/tmp/runner \
  dhanrajsubbaianind/github-runner-school:latest
```

> `--restart unless-stopped` ensures Docker auto-restarts containers on Mac reboot — **no need to re-register after restart**.

#### Step 3 — Verify Runners Are Online

```bash
gh api repos/dhanrajsr/terraform-infra/actions/runners \
  --jq '.runners[] | {name, status}'

gh api repos/dhanrajsr/school-api-lambda/actions/runners \
  --jq '.runners[] | {name, status}'

gh api repos/dhanrajsr/school-ui/actions/runners \
  --jq '.runners[] | {name, status}'
```

Expected output:
```json
{"name":"runner-terraform","status":"online"}
{"name":"runner-school-api-lambda","status":"online"}
{"name":"runner-school-ui","status":"online"}
```

---

### Re-registering Runners (After Token Expiry or Corruption)

If runners show `offline` and fail with `Not Found` or `Not configured`, the registration is stale.
Follow these steps to clean up and re-register:

#### Step 1 — Stop and Remove Old Containers

```bash
docker rm -f runner-terraform runner-school-api-lambda runner-school-ui
```

#### Step 2 — Remove Stale Registrations from GitHub

```bash
for repo in terraform-infra school-api-lambda school-ui; do
  IDS=$(gh api repos/dhanrajsr/$repo/actions/runners \
    --jq '.runners[] | select(.status=="offline") | .id')
  for id in $IDS; do
    gh api --method DELETE repos/dhanrajsr/$repo/actions/runners/$id \
      && echo "Removed stale runner $id from $repo"
  done
done
```

> If a runner is currently executing a job it cannot be deleted — it will disappear automatically after the job finishes.

#### Step 3 — Re-register

Follow [First-Time Runner Setup](#first-time-runner-setup) from Step 1 above.

---

### Runner Management Reference

| Task | Command |
|------|---------|
| Check runner status | `docker ps \| grep runner` |
| View runner logs | `docker logs runner-terraform -f` |
| Stop a runner | `docker stop runner-terraform` |
| Start a stopped runner | `docker start runner-terraform` |
| Remove a runner | `docker rm -f runner-terraform` |
| List GitHub registrations | `gh api repos/dhanrajsr/<repo>/actions/runners --jq '.runners[]'` |

### Why Runners Go Offline After Mac Reboot

Docker containers started **without** `--restart unless-stopped` stop when the Mac shuts down and do not restart automatically. The runner process inside registers a token at startup — if the container is recreated it needs a fresh token.

With `--restart unless-stopped`:
- Docker restarts the container after Mac reboot
- The runner reconnects to GitHub using its persisted registration (not the token — token is only needed once)
- No manual intervention needed

---

## Prerequisites

### 1. AWS OIDC — Keyless Authentication

GitHub Actions authenticates to AWS without access keys using OIDC (OpenID Connect).

IAM role: `github-actions-terraform`

Trust policy — repos allowed to assume the role:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::497041484428:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:dhanrajsr/terraform-infra:*",
          "repo:dhanrajsr/school-api-lambda:*",
          "repo:dhanrajsr/school-ui:*"
        ]
      }
    }
  }]
}
```

**To add a new repo** to the trust policy:
```bash
# Get current policy
aws iam get-role --role-name github-actions-terraform \
  --query 'Role.AssumeRolePolicyDocument' --output json > trust-policy.json

# Edit trust-policy.json — add new repo to StringLike array

# Apply updated policy
aws iam update-assume-role-policy \
  --role-name github-actions-terraform \
  --policy-document file://trust-policy.json
```

### 2. GitHub Secrets & Variables

**`dhanrajsr/terraform-infra`**

| Name | Type | Value |
|------|------|-------|
| `AWS_ROLE_ARN` | Secret | `arn:aws:iam::497041484428:role/github-actions-terraform` |
| `SCHOOL_DB_PASSWORD` | Secret | RDS master password |
| `AZURE_CLIENT_ID` | Secret | Azure service principal client ID |
| `AZURE_TENANT_ID` | Secret | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Secret | Azure subscription ID |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Secret | GCP workload identity provider |
| `GCP_SERVICE_ACCOUNT` | Secret | GCP service account email |

> **Password rules for `SCHOOL_DB_PASSWORD`**: Must not contain `/`, `@`, `"`, or spaces. Use alphanumeric + `!#$%^&*()_+-=` only.

**`dhanrajsr/school-api-lambda`**

| Name | Type | Value |
|------|------|-------|
| `AWS_ROLE_ARN` | Secret | `arn:aws:iam::497041484428:role/github-actions-terraform` |

**`dhanrajsr/school-ui`**

| Name | Type | Value |
|------|------|-------|
| `AWS_ROLE_ARN` | Secret | `arn:aws:iam::497041484428:role/github-actions-terraform` |
| `VITE_API_BASE_URL` | Secret | `https://cgaoh0ja3l.execute-api.us-east-1.amazonaws.com/api` |
| `AWS_ACCOUNT_ID` | Variable | `497041484428` |

---

## Deployment Order

> **Important**: Follow this order on a fresh deployment. Lambda creation fails if the JAR is not in S3 yet.

```
1. Terraform: aws-school   (creates S3 JAR bucket, RDS, Lambda stub, API Gateway)
   └── Will fail on Lambda if JAR missing — that's OK, continue to step 2

2. school-api-lambda CI    (builds fat JAR, uploads to S3, updates Lambda)

3. Terraform: aws-school   (re-run apply — Lambda now succeeds with JAR in S3)

4. Terraform: aws-school-ui (creates S3 UI bucket, CloudFront distribution)

5. school-ui CI            (builds React app, deploys to S3, invalidates CloudFront)
```

---

## Step 1 — Provision Infrastructure (Terraform)

### Trigger

```
terraform-infra → Actions → Terraform → Run workflow
```

### 1a. School Backend (RDS + Lambda + API Gateway)

| Input | Value |
|-------|-------|
| Service | `aws-school` |
| Environment | `dev` |
| Action | `plan` (verify first), then `apply` |

**Resources created:**

| Resource | Name | Details |
|----------|------|---------|
| S3 Bucket | `school-lambda-jar-497041484428-dev` | Stores Lambda JAR, versioning enabled |
| DB Subnet Group | `school-dev` | Uses EKS VPC public subnets |
| Security Group | `school-rds-dev` | Allows port 5432 from `0.0.0.0/0` (dev only) |
| RDS Instance | `school-dev` | PostgreSQL 16, db.t3.micro, 20GB, publicly accessible |
| IAM Role | `school-lambda-dev` | `AWSLambdaBasicExecutionRole` + S3 GetObject |
| Lambda Function | `school-api-dev` | Java 21, 512MB, 30s timeout |
| API Gateway | `school-api-dev` | HTTP API, `$default` → Lambda |
| CloudWatch Logs | `/aws/lambda/school-api-dev` | 7 day retention |
| CloudWatch Logs | `/aws/apigateway/school-api-dev` | 7 day retention |

### 1b. School UI (S3 + CloudFront)

| Input | Value |
|-------|-------|
| Service | `aws-school-ui` |
| Environment | `dev` |
| Action | `plan` (verify first), then `apply` |

**Resources created:**

| Resource | Name | Details |
|----------|------|---------|
| S3 Bucket | `school-ui-497041484428-dev` | Private, versioning enabled |
| Origin Access Control | `school-ui-dev` | CloudFront → S3 sigv4 signing |
| CloudFront Distribution | `school-ui-dev` | HTTPS redirect, SPA 403/404 fallback |
| S3 Bucket Policy | — | Allows only CloudFront service principal |

### Get Outputs After Apply

```bash
# API Gateway URL
aws apigatewayv2 get-apis --region us-east-1 \
  --query 'Items[?Name==`school-api-dev`].[ApiId,ApiEndpoint]' \
  --output table

# CloudFront URL
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='school-ui-dev'].[DomainName,Id]" \
  --output table
```

---

## Step 2 — Build & Upload Lambda JAR

### What it does

`school-api-lambda` CI pipeline:
1. Runs `mvn clean package` — Maven Shade plugin bundles all dependencies into a single fat JAR (~43MB)
2. Uploads JAR to `s3://school-lambda-jar-497041484428-dev/school-api-lambda.jar`
3. If Lambda function already exists, calls `aws lambda update-function-code` to deploy immediately

### Trigger

```
school-api-lambda → Actions → CI — Build & Upload Lambda JAR → Run workflow
```

Or automatically on every push to `main`.

### Why Maven Shade Instead of Spring Boot Plugin?

Spring Boot's default repackage creates a nested JAR format that Lambda cannot execute directly.
Maven Shade flattens all dependencies into a single JAR with a standard classpath — the format Lambda expects.

```xml
<!-- Shade handles packaging — Spring Boot repackage is disabled -->
<plugin>
  <artifactId>maven-shade-plugin</artifactId>
  <version>3.3.0</version>
  <executions>
    <execution>
      <phase>package</phase>
      <goals><goal>shade</goal></goals>
    </execution>
  </executions>
</plugin>

<plugin>
  <artifactId>spring-boot-maven-plugin</artifactId>
  <executions>
    <execution>
      <id>repackage</id>
      <phase>none</phase>  <!-- disabled -->
    </execution>
  </executions>
</plugin>
```

---

## Step 3 — Deploy Frontend (school-ui)

### What it does

`school-ui` CI pipeline:
1. Runs `npm ci` — installs exact versions from `package-lock.json`
2. Runs `npm run build` (Vite) — injects `VITE_API_BASE_URL` at build time into the JS bundle
3. Syncs `dist/` to S3:
   - JS/CSS assets: `Cache-Control: public, max-age=31536000, immutable` (1 year — hash in filename ensures cache busting)
   - `index.html`: `Cache-Control: no-cache` (always fetched fresh)
4. Invalidates CloudFront cache (`/*`) so users get the new version immediately

### Trigger

```
school-ui → Actions → CI — Build & Deploy UI → Run workflow
```

Or automatically on every push to `main`.

### How API URL is Injected

The `VITE_API_BASE_URL` secret is baked into the JavaScript bundle at build time by Vite:

```js
// src/api/axios.js
const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080/api',
});
```

For local development, the fallback `http://localhost:8080/api` is used automatically.

---

## Application Code — school-api-lambda

### How Spring Boot Runs Inside Lambda

Normal Spring Boot starts an embedded Tomcat server and listens on a port.
Lambda has no concept of ports — it invokes a handler function per request.

The `aws-serverless-java-container` library bridges the gap:

```
API Gateway event (JSON)
         ↓
StreamLambdaHandler.handleRequest()     ← Lambda entry point
         ↓
SpringBootLambdaContainerHandler        ← aws-serverless-java-container
         ↓
AwsProxyHttpServletRequest              ← converts JSON event to HttpServletRequest
         ↓
Spring DispatcherServlet                ← routes to correct @RestController
         ↓
AwsProxyResponse                        ← converts HttpServletResponse to JSON
         ↓
API Gateway response
```

**StreamLambdaHandler** (entry point):
```java
public class StreamLambdaHandler implements RequestStreamHandler {

    // Spring Boot initialises once (static) — stays warm between invocations
    private static final SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> handler;

    static {
        handler = SpringBootLambdaContainerHandler.getAwsProxyHandler(SchoolApiApplication.class);
    }

    @Override
    public void handleRequest(InputStream in, OutputStream out, Context ctx) throws IOException {
        handler.proxyStream(in, out, ctx);
    }
}
```

### Cold Start vs Warm

- **Cold start** (~10s): Lambda allocates a new container, JVM boots, Spring context loads, DB connection pool initialises
- **Warm** (~50ms): Same container reused, Spring context already loaded, only request processing happens
- **HikariCP pool size = 2**: Keeps connection count low — Lambda can spawn many containers simultaneously, each with its own pool

### Data Model

```
Branch (1) ──── (N) Course (N) ──── (M) Student
                                         │
                                    (1)  │ (N)
                                        Fees
```

| Entity | Table | Key Fields |
|--------|-------|-----------|
| Branch | `branches` | id, name, location, contact |
| Course | `courses` | id, name, duration, branch_id |
| Student | `students` | id, name, age, dob, address |
| Fees | `fees` | id, amount, paid_date, student_id |

Hibernate `ddl-auto: update` creates/updates tables automatically on Lambda startup.

### Application Configuration (`application.yml`)

```yaml
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://localhost:5432/schooldb}   # injected by Lambda env
    username: ${DB_USERNAME:school}
    password: ${DB_PASSWORD:school123}
    hikari:
      maximum-pool-size: 2      # low — Lambda parallelism means many pools
      connection-timeout: 10000
  jpa:
    hibernate:
      ddl-auto: update          # auto-creates tables on first boot
```

Environment variables injected by Lambda (set in Terraform):

| Variable | Value |
|----------|-------|
| `DB_URL` | `jdbc:postgresql://<rds-endpoint>/schooldb` |
| `DB_USERNAME` | `school` |
| `DB_PASSWORD` | From `SCHOOL_DB_PASSWORD` GitHub secret |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | `update` |

### CORS Configuration

Browser sends an `OPTIONS` preflight before POST/PUT/DELETE requests.
Spring Boot handles CORS directly (not API Gateway) because `payload_format_version = "1.0"` bypasses API Gateway's built-in CORS handling.

```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns("*")       // all origins — restrict in prod
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(false);
    }
}
```

---

## API Reference

Base URL: `https://cgaoh0ja3l.execute-api.us-east-1.amazonaws.com`

### Branches

| Method | Path | Description | Request Body |
|--------|------|-------------|-------------|
| GET | `/api/branches` | List all branches | — |
| GET | `/api/branches/{id}` | Get branch by ID | — |
| POST | `/api/branches` | Create branch | `{"name":"", "location":"", "contact":""}` |
| PUT | `/api/branches/{id}` | Update branch | `{"name":"", "location":"", "contact":""}` |
| DELETE | `/api/branches/{id}` | Delete branch | — |

### Courses

| Method | Path | Description | Request Body |
|--------|------|-------------|-------------|
| GET | `/api/courses` | List all courses | — |
| GET | `/api/courses/{id}` | Get course by ID | — |
| POST | `/api/courses` | Create course | `{"name":"", "duration":"", "branchId":1}` |
| PUT | `/api/courses/{id}` | Update course | `{"name":"", "duration":"", "branchId":1}` |
| DELETE | `/api/courses/{id}` | Delete course | — |

### Students

| Method | Path | Description | Request Body |
|--------|------|-------------|-------------|
| GET | `/api/students` | List all students | — |
| GET | `/api/students/{id}` | Get student by ID | — |
| POST | `/api/students` | Create student | `{"name":"", "age":20, "dob":"2004-01-01", "address":"", "courseIds":[1,2]}` |
| PUT | `/api/students/{id}` | Update student | `{"name":"", "age":20, "address":""}` |
| DELETE | `/api/students/{id}` | Delete student | — |

### Fees

| Method | Path | Description | Request Body |
|--------|------|-------------|-------------|
| GET | `/api/fees` | List all fees | — |
| GET | `/api/fees/{id}` | Get fee record by ID | — |
| POST | `/api/fees` | Create fee record | `{"amount":5000, "paidDate":"2026-04-01", "studentId":1}` |
| PUT | `/api/fees/{id}` | Update fee record | `{"amount":5000, "paidDate":"2026-04-01"}` |
| DELETE | `/api/fees/{id}` | Delete fee record | — |

### Test with curl

```bash
BASE=https://cgaoh0ja3l.execute-api.us-east-1.amazonaws.com

# Create a branch
curl -s -X POST $BASE/api/branches \
  -H "Content-Type: application/json" \
  -d '{"name":"Engineering","location":"Chennai","contact":"044-12345678"}' | jq .

# Create a course under the branch
curl -s -X POST $BASE/api/courses \
  -H "Content-Type: application/json" \
  -d '{"name":"Computer Science","duration":"4 years","branchId":1}' | jq .

# Create a student enrolled in the course
curl -s -X POST $BASE/api/students \
  -H "Content-Type: application/json" \
  -d '{"name":"Ravi Kumar","age":20,"dob":"2004-06-15","address":"Chennai","courseIds":[1]}' | jq .

# Record a fee payment
curl -s -X POST $BASE/api/fees \
  -H "Content-Type: application/json" \
  -d '{"amount":25000,"paidDate":"2026-04-06","studentId":1}' | jq .
```

---

## Custom Domain Setup

To serve the UI at `school.devopscab.com` instead of the CloudFront default domain.

### Step 1 — Request SSL Certificate (ACM)

> Certificate **must** be in `us-east-1` for CloudFront — even if your resources are elsewhere.

1. AWS Console → **Certificate Manager** → confirm region is `us-east-1`
2. **Request certificate** → **Request a public certificate**
3. Domain name: `school.devopscab.com`
4. Validation method: **DNS validation**
5. Click **Request**
6. Open the pending certificate — note the CNAME validation record

### Step 2 — DNS Validation

Add the CNAME record ACM provides to your DNS provider:

| Type | Name | Value |
|------|------|-------|
| CNAME | `_<token>.school.devopscab.com` | `_<token>.acm-validations.aws` |

Wait 5–10 minutes. ACM status changes to **Issued**.

### Step 3 — Attach Certificate to CloudFront

1. CloudFront → Distributions → `school-ui-dev` → **Edit**
2. **General** tab:
   - Alternate domain names: `school.devopscab.com`
   - Custom SSL certificate: select the ACM certificate from Step 1
3. Click **Save changes** (propagation takes 5–15 minutes)

### Step 4 — Point Domain to CloudFront (DNS)

Add a CNAME in your DNS provider:

| Type | Name | Value |
|------|------|-------|
| CNAME | `school.devopscab.com` | `d15oeotzu3ugz0.cloudfront.net` |

### Step 5 — Test

```bash
curl -I https://school.devopscab.com
# Expect: HTTP/2 200
```

---

## CI/CD Pipeline Reference

### terraform-infra — `terraform.yml`

Triggered manually via `workflow_dispatch`.

| Input | Options |
|-------|---------|
| `service` | `aws-eks`, `aws-school`, `aws-school-ui`, `azure-aks`, `gcp-gke` |
| `environment` | `dev`, `sit`, `uat`, `prod` |
| `action` | `plan`, `apply`, `destroy` |

Jobs:
- `terraform-aws` — provisions EKS (when service=`aws-eks`)
- `terraform-school` — provisions school backend (when service=`aws-school`)
- `terraform-school-ui` — provisions school frontend hosting (when service=`aws-school-ui`)
- `terraform-azure` — provisions AKS (when service=`azure-aks`)
- `terraform-gcp` — provisions GKE (when service=`gcp-gke`)

### school-api-lambda — `ci.yml`

| Trigger | When |
|---------|------|
| Push to `main` | Automatic |
| `workflow_dispatch` | Manual with `environment` input |

Steps: Checkout → OIDC Auth → `mvn clean package` → S3 upload → Lambda update

### school-ui — `ci.yml`

| Trigger | When |
|---------|------|
| Push to `main` | Automatic |
| `workflow_dispatch` | Manual with `environment` input |

Steps: Checkout → OIDC Auth → `npm ci` → `npm run build` → S3 sync → CloudFront invalidation

---

## Troubleshooting

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `InvalidRequestEventException: not a valid request from Amazon API Gateway` | API Gateway sending payload format 2.0; `aws-serverless-java-container` expects 1.0 | Set `payload_format_version = "1.0"` in `apigateway.tf` integration |
| `NoSuchKey` on Lambda create | JAR not in S3 | Run school-api-lambda CI pipeline first, then re-apply Terraform |
| `OPTIONS 403` (CORS failure) | `CorsConfig.java` only allowed `localhost` origins | Use `allowedOriginPatterns("*")` instead of `allowedOrigins(...)` |
| `InvalidSubnet: No default subnet detected` | RDS needs an explicit subnet group | Add `aws_db_subnet_group` with VPC public subnets |
| `InvalidParameterValue: MasterUserPassword is not valid` | Password contains `/`, `@`, `"`, or space | Use alphanumeric + `!#$%^&*()_+-=` only |
| `Credentials could not be loaded` (OIDC) | Repo not in IAM trust policy | Add `repo:dhanrajsr/<repo>:*` to `github-actions-terraform` trust policy |
| `Source Account ID is needed` | `AWS_ROLE_ARN` secret empty or set to role name instead of ARN | Set secret to full ARN: `arn:aws:iam::497041484428:role/github-actions-terraform` |
| Lambda returns `500 Internal Server Error` | Spring Boot startup failure or DB connection error | Check CloudWatch logs: `aws logs tail /aws/lambda/school-api-dev --since 10m` |
| Lambda returns `404` | Wrong URL path — controllers are under `/api/` | Use `/api/branches` not `/branches` |
| UI shows "Not Secure" | Mixed content — page on HTTPS but API calls on HTTP | Ensure `VITE_API_BASE_URL` secret starts with `https://` |
| CloudFront shows old content after deploy | Cache not invalidated | CI pipeline runs `aws cloudfront create-invalidation --paths "/*"` automatically |
| Runner not picking up jobs | Runner offline or wrong labels | Check `gh api repos/dhanrajsr/<repo>/actions/runners` and restart container |

### Useful Diagnostic Commands

```bash
# Check Lambda logs live
aws logs tail /aws/lambda/school-api-dev --region us-east-1 --follow

# Test API directly
curl -s https://cgaoh0ja3l.execute-api.us-east-1.amazonaws.com/api/branches | jq .

# Check what's in Lambda JAR bucket
aws s3 ls s3://school-lambda-jar-497041484428-dev/

# Check CloudFront distribution status
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='school-ui-dev'].[Status,DomainName]" \
  --output table

# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier school-dev \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' \
  --output table

# Check GitHub Actions runners
gh api repos/dhanrajsr/school-api-lambda/actions/runners --jq '.runners[] | {name, status, busy}'
```
