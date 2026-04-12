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
  organization_name = "WBZTWSY"
  account_name      = "KH99814"
  user              = "PATCHIT"
  role              = "ACCOUNTADMIN"
  warehouse         = "COMPUTE_WH"
  # Auth: password via SNOWFLAKE_PASSWORD env var (local + CI).
  # To use RSA key pair instead: set authenticator="SNOWFLAKE_JWT" and private_key=file(...)
  # after running: ALTER USER PATCHIT SET RSA_PUBLIC_KEY='...' in Snowflake.
}
