terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "databricks_workspace_url" {}
variable "databricks_account_id" {}
variable "workspace_service_user_client_id" {}
variable "workspace_service_user_client_secret" {}
variable "workspace_service_user_id" {}
variable "aws_access_key_id" {}
variable "aws_secret_access_key" {}
variable "databricks_terraform_account_client_id" {}
variable "databricks_terraform_account_secret" {}

variable "tags" {
  default = {}
}
variable "region" {
  default = "ca-central-1"
}

variable "databricks_workspace_ids" {
  description = <<EOT
  List of Databricks workspace IDs to be enabled with Unity Catalog.
  Enter with square brackets and double quotes
  e.g. ["111111111", "222222222"]
  EOT
  type        = list(string)
}

variable "databricks_users" {
  description = <<EOT
  List of Databricks users to be added at account-level for Unity Catalog.
  Enter with square brackets and double quotes
  e.g ["first.last@domain.com", "second.last@domain.com"]
  EOT
  type        = list(string)
}

variable "databricks_metastore_admins" {
  description = <<EOT
  List of Admins to be added at account-level for Unity Catalog.
  Enter with square brackets and double quotes
  e.g ["first.admin@domain.com", "second.admin@domain.com"]
  EOT
  type        = list(string)
}

variable "unity_admin_group" {
  description = "Name of the admin group. This group will be set as the owner of the Unity Catalog metastore"
  type        = string
}

//generate a random string as the prefix for AWS resources, to ensure uniqueness
resource "random_string" "naming" {
  special = false
  upper   = false
  length  = 6
}

locals {
  prefix = "demo${random_string.naming.result}"
}

provider "aws" {
  region     = var.region
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}
resource "aws_s3_bucket" "learning_bucket" {
  bucket = "${local.prefix}-alexis-learning-databricks"
  tags = {
    Name = "${local.prefix}-metastore"
  }
}

resource "aws_s3_bucket_versioning" "learning_bucket_versioning" {
  bucket = aws_s3_bucket.learning_bucket.id
  versioning_configuration {
    status = "Suspended"
  }
}


provider "databricks" {
  alias         = "mws"
  account_id    = var.databricks_account_id
  client_id     = var.databricks_terraform_account_client_id
  client_secret = var.databricks_terraform_account_secret
}

provider "databricks" {
  alias         = "workspace"
  host          = var.databricks_workspace_url
  client_id     = var.workspace_service_user_client_id
  client_secret = var.workspace_service_user_client_secret
}

data "aws_iam_policy_document" "passrole_for_uc" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"]
      type        = "AWS"
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}

resource "aws_iam_policy" "unity_metastore" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.prefix}-databricks-unity-metastore"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          aws_s3_bucket.learning_bucket.arn,
          "${aws_s3_bucket.learning_bucket.arn}/*"
        ],
        "Effect" : "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "sample_data" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.prefix}-databricks-sample-data"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          "arn:aws:s3:::databricks-datasets-oregon/*",
          "arn:aws:s3:::databricks-datasets-oregon"

        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = {
    Name = "${local.prefix}-unity-catalog IAM policy"
  }
}

resource "aws_iam_role" "metastore_data_access2" {
  name                = "${local.prefix}-uc-access-3"
  assume_role_policy  = data.aws_iam_policy_document.passrole_for_uc.json
  managed_policy_arns = [aws_iam_policy.unity_metastore.arn, aws_iam_policy.sample_data.arn]
  tags = {
    Name = "${local.prefix}-unity-catalog IAM role"
  }
}

resource "databricks_user" "unity_users" {
  provider  = databricks.mws
  for_each  = toset(concat(var.databricks_users, var.databricks_metastore_admins))
  user_name = each.key
  force     = true
}

resource "databricks_group" "admin_group" {
  provider     = databricks.mws
  display_name = var.unity_admin_group
}

resource "databricks_group_member" "admin_group_member" {
  provider  = databricks.mws
  for_each  = toset(var.databricks_metastore_admins)
  group_id  = databricks_group.admin_group.id
  member_id = databricks_user.unity_users[each.value].id
}

resource "databricks_group_member" "admin_service_user" {
  provider  = databricks.mws
  group_id  = databricks_group.admin_group.id
  member_id = var.workspace_service_user_id
}

resource "databricks_user_role" "metastore_admin" {
  provider = databricks.mws
  for_each = toset(var.databricks_metastore_admins)
  user_id  = databricks_user.unity_users[each.value].id
  role     = "account_admin"
}

resource "databricks_metastore" "this" {
  provider      = databricks.workspace
  name          = "metastore_aws_ca_central_1"
  storage_root  = "s3://${aws_s3_bucket.learning_bucket.id}/metastore"
  owner         = var.unity_admin_group
  force_destroy = true
}

resource "databricks_metastore_data_access" "this" {
  provider     = databricks.workspace
  metastore_id = databricks_metastore.this.id
  name         = aws_iam_role.metastore_data_access2.name
  aws_iam_role {
    role_arn = aws_iam_role.metastore_data_access2.arn
  }
  is_default = true
}

resource "databricks_metastore_assignment" "default_metastore" {
  provider             = databricks.workspace
  for_each             = toset(var.databricks_workspace_ids)
  workspace_id         = each.key
  metastore_id         = databricks_metastore.this.id
  default_catalog_name = "hive_metastore"
}