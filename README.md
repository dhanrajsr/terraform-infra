# Terraform Infrastructure

Multi-cloud infrastructure provisioning for EKS (AWS), AKS (Azure), and GKE (GCP) using Terraform and GitHub Actions with OIDC keyless authentication.

---

## Repository Structure

```
terraform-infra/
├── .github/workflows/
│   ├── terraform.yml        # Main Terraform pipeline
│   ├── bootstrap.yml        # EKS post-provisioning (Cilium, ALB, ArgoCD)
│   ├── runner.yml           # Build terraform runner image
│   └── school-runner.yml    # Build school app runner image
├── aws/us-east-1/
│   └── dev/
│       ├── eks/             # EKS cluster workspace
│       ├── school/          # School App (Lambda + RDS + API Gateway)
│       └── school-ui/       # School UI (S3 + CloudFront)
├── modules/
│   ├── eks/                 # EKS cluster module
│   ├── school-app/          # Lambda + RDS + API Gateway module
│   └── school-ui/           # S3 + CloudFront module
├── runner/                  # Terraform runner Dockerfile
└── school-runner/           # School app runner Dockerfile
```

---

## Phase 1 — School App Deployment (Lambda + API Gateway + RDS)

### Architecture

```
Browser / school-ui (CloudFront + S3)
           ↓
   API Gateway (HTTP API)
   $default catch-all route
           ↓
   Lambda (school-api-dev)
   Java 21 — Spring Boot fat JAR
           ↓
   RDS PostgreSQL 16 (school-dev)
   db.t3.micro — public subnet
```

### Prerequisites

#### 1. AWS OIDC Trust — GitHub Actions Keyless Auth

An IAM role `github-actions-terraform` must exist with a trust policy allowing these repos:

```json
{
  "StringLike": {
    "token.actions.githubusercontent.com:sub": [
      "repo:dhanrajsr/terraform-infra:*",
      "repo:dhanrajsr/school-api-lambda:*",
      "repo:dhanrajsr/school-ui:*"
    ]
  }
}
```

To add a new repo to the trust policy:
```bash
aws iam get-role --role-name github-actions-terraform \
  --query 'Role.AssumeRolePolicyDocument' --output json
# Edit and re-apply with:
aws iam update-assume-role-policy --role-name github-actions-terraform \
  --policy-document file://trust-policy.json
```

#### 2. GitHub Secrets

| Repo | Secret | Value |
|------|--------|-------|
| `terraform-infra` | `AWS_ROLE_ARN` | `arn:aws:iam::497041484428:role/github-actions-terraform` |
| `terraform-infra` | `SCHOOL_DB_PASSWORD` | RDS master password (no `/`, `@`, `"`, or spaces) |
| `school-api-lambda` | `AWS_ROLE_ARN` | Same role ARN |
| `school-ui` | `AWS_ROLE_ARN` | Same role ARN |
| `school-ui` | `VITE_API_BASE_URL` | `https://<api-gateway-id>.execute-api.us-east-1.amazonaws.com/api` |

| Repo | Variable | Value |
|------|----------|-------|
| `school-ui` | `AWS_ACCOUNT_ID` | `497041484428` |

#### 3. Self-Hosted Runners

School runner image must be built and runners registered for:
- `dhanrajsr/school-api-lambda`
- `dhanrajsr/school-ui`

Build the runner image:
```
terraform-infra → Actions → Build School Runner Image → Run workflow
```

Start runners (replace tokens with generated registration tokens):
```bash
docker run -d \
  -e REPO_URL=https://github.com/dhanrajsr/school-api-lambda \
  -e RUNNER_TOKEN=<token> \
  -e RUNNER_NAME=runner-school-api-lambda \
  -e LABELS=self-hosted,docker,linux \
  dhanrajsubbaianind/github-runner-school:latest
```

---

### Step 1 — Provision Infrastructure (terraform-infra)

Trigger the Terraform workflow for each service:

```
terraform-infra → Actions → Terraform → Run workflow
```

#### 1a. School App (RDS + Lambda + API Gateway)

| Input | Value |
|-------|-------|
| Service | `aws-school` |
| Environment | `dev` |
| Action | `plan` then `apply` |

This creates:
- S3 bucket: `school-lambda-jar-497041484428-dev` (Lambda JAR storage)
- RDS PostgreSQL: `school-dev` (db.t3.micro, public subnet, port 5432)
- Lambda function: `school-api-dev` (Java 21, 512MB, 30s timeout)
- API Gateway: HTTP API with `$default` catch-all route → Lambda

> **Note:** Lambda creation will fail if the JAR does not exist in S3 yet.
> Run Step 2 first if this is a fresh deployment, then re-run apply.

#### 1b. School UI (S3 + CloudFront)

| Input | Value |
|-------|-------|
| Service | `aws-school-ui` |
| Environment | `dev` |
| Action | `plan` then `apply` |

This creates:
- S3 bucket: `school-ui-497041484428-dev` (React static files)
- CloudFront distribution with SPA fallback (403/404 → index.html)
- Origin Access Control (S3 only accessible via CloudFront)

---

### Step 2 — Build & Upload Lambda JAR (school-api-lambda)

```
school-api-lambda → Actions → CI — Build & Upload Lambda JAR → Run workflow
```

| Input | Value |
|-------|-------|
| Environment | `dev` |

This:
1. Builds Spring Boot fat JAR using Maven Shade plugin
2. Uploads to `s3://school-lambda-jar-497041484428-dev/school-api-lambda.jar`
3. Updates Lambda function code if it already exists

> Triggers automatically on every push to `main`.

---

### Step 3 — Deploy Frontend (school-ui)

```
school-ui → Actions → CI — Build & Deploy UI → Run workflow
```

| Input | Value |
|-------|-------|
| Environment | `dev` |

This:
1. Builds React app with `VITE_API_BASE_URL` injected at build time
2. Syncs `dist/` to S3 (`index.html` with `no-cache`, assets with long-lived cache)
3. Invalidates CloudFront cache (`/*`)

> Triggers automatically on every push to `main`.

---

### Step 4 — Get Endpoints

After all steps complete:

```bash
# API Gateway URL
aws apigatewayv2 get-apis --region us-east-1 \
  --query 'Items[?Name==`school-api-dev`].ApiEndpoint' --output text

# CloudFront URL
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='school-ui-dev'].DomainName" \
  --output text
```

Current endpoints (dev):

| Service | URL |
|---------|-----|
| API Gateway | `https://cgaoh0ja3l.execute-api.us-east-1.amazonaws.com` |
| CloudFront | `https://d15oeotzu3ugz0.cloudfront.net` |
| Custom Domain | `https://school.devopscab.com` |

---

### Step 5 — Custom Domain (Optional)

To use your own domain (e.g. `school.devopscab.com`):

1. **Request SSL certificate** in AWS ACM (must be **us-east-1**):
   - Go to ACM → Request certificate → Public → enter `school.devopscab.com`
   - Validation method: DNS

2. **Add DNS validation CNAME** in your DNS provider:
   ```
   _<token>.school.devopscab.com → _<token>.acm-validations.aws
   ```
   Wait for ACM status to show **Issued**.

3. **Attach certificate to CloudFront**:
   - CloudFront → Distributions → school-ui-dev → Edit
   - Alternate domain names: `school.devopscab.com`
   - Custom SSL certificate: select the ACM certificate

4. **Add CNAME in DNS** pointing to CloudFront:
   ```
   school.devopscab.com → d15oeotzu3ugz0.cloudfront.net
   ```

---

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/branches` | List all branches |
| POST | `/api/branches` | Create branch |
| GET | `/api/courses` | List all courses |
| POST | `/api/courses` | Create course |
| GET | `/api/students` | List all students |
| POST | `/api/students` | Create student |
| GET | `/api/fees` | List all fees |
| POST | `/api/fees` | Create fee record |

---

### Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Lambda `InvalidRequestEventException` | Payload format mismatch | Set `payload_format_version = "1.0"` in API Gateway integration |
| Lambda `NoSuchKey` on create | JAR not in S3 | Run school-api-lambda CI first |
| `OPTIONS 403` (CORS) | Spring Boot not allowing origin | Use `allowedOriginPatterns("*")` in `CorsConfig.java` |
| RDS `InvalidSubnet` | No default VPC subnets | Add `aws_db_subnet_group` using explicit subnets |
| OIDC auth failure | Repo not in IAM trust policy | Add `repo:dhanrajsr/<repo>:*` to trust policy |
| RDS bad password | Special chars `/`, `@`, `"`, space | Use only alphanumeric + `!#$%^&*()_+-=` |
