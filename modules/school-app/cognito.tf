# ─── Cognito User Pool ────────────────────────────────────────────
resource "aws_cognito_user_pool" "school" {
  name = "school-user-pool-${var.environment}"

  # Users sign in with email
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # Email verification message
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "School App - Verify your email"
    email_message        = "Your verification code is {####}"
  }

  # User attributes
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 100
    }
  }

  schema {
    attribute_data_type = "String"
    name                = "name"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 100
    }
  }

  # Account recovery via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = merge(var.tags, { Name = "school-user-pool-${var.environment}" })
}

# ─── Cognito User Pool Client (for React UI) ─────────────────────
resource "aws_cognito_user_pool_client" "web" {
  name         = "school-web-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.school.id

  # No client secret — public SPA client
  generate_secret = false

  # Auth flows — SRP is secure browser-based flow
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  # Token validity
  access_token_validity  = 1   # hours
  id_token_validity      = 1   # hours
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Allowed callback/logout URLs (CloudFront domain + localhost for dev)
  callback_urls = compact([
    "https://${var.ui_domain != "" ? var.ui_domain : "localhost:5173"}",
    "http://localhost:5173",
  ])

  logout_urls = compact([
    "https://${var.ui_domain != "" ? var.ui_domain : "localhost:5173"}",
    "http://localhost:5173",
  ])

  supported_identity_providers = ["COGNITO"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
}

# ─── Cognito User Pool Domain (for Hosted UI) ────────────────────
resource "aws_cognito_user_pool_domain" "school" {
  domain       = "school-${var.environment}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.school.id
}

# ─── Current AWS account (needed for unique Cognito domain) ──────
data "aws_caller_identity" "current" {}
