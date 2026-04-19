terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = ">= 0.92.0, < 1.0.0"
    }
  }
}

provider "snowflake" {
  # Set via env vars: SNOWFLAKE_ORGANIZATION_NAME, SNOWFLAKE_ACCOUNT_NAME,
  # SNOWFLAKE_USER, SNOWFLAKE_PASSWORD — never hardcode here.
  # See .env.example at the repo root.
  role      = var.snowflake_role
  warehouse = var.snowflake_warehouse
  # Auth: password via SNOWFLAKE_PASSWORD env var (local + CI).
  # To use RSA key pair instead: set authenticator="SNOWFLAKE_JWT" and private_key=file(...)
  # after running: ALTER USER <user> SET RSA_PUBLIC_KEY='...' in Snowflake.
}
