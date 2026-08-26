##############################################
# 1. Réseau 3-tiers (web / app / data)
##############################################
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "web" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-web-${count.index}" }
}

resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.project_name}-app-${count.index}" }
}

resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.project_name}-data-${count.index}" }
}

##############################################
# 2. KMS - clés gérées par le client (CMK)
##############################################
resource "aws_kms_key" "app_key" {
  description             = "CMK pour chiffrement S3/RDS/EBS - ${var.project_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags = { Name = "${var.project_name}-cmk" }
}

resource "aws_kms_alias" "app_key" {
  name          = "alias/${var.project_name}-cmk"
  target_key_id = aws_kms_key.app_key.key_id
}

##############################################
# 3. Secrets Manager + RDS (tier data) chiffré
##############################################
resource "random_password" "db_master" {
  length  = 24
  special = true
}

resource "aws_secretsmanager_secret" "db_secret" {
  name       = "${var.project_name}/rds/master"
  kms_key_id = aws_kms_key.app_key.arn
}

resource "aws_secretsmanager_secret_version" "db_secret_v" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_master.result
  })
}

resource "aws_secretsmanager_secret_rotation" "db_rotation" {
  secret_id           = aws_secretsmanager_secret.db_secret.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_db_subnet_group" "data" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_db_instance" "app_db" {
  identifier              = "${var.project_name}-db"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.app_key.arn
  db_subnet_group_name    = aws_db_subnet_group.data.name
  username                = var.db_username
  password                = random_password.db_master.result
  skip_final_snapshot     = true
  publicly_accessible     = false
  backup_retention_period = 7
  vpc_security_group_ids  = [aws_security_group.data_tier.id]
}

resource "aws_security_group" "data_tier" {
  name   = "${var.project_name}-sg-data"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_tier.id]
  }
}

resource "aws_security_group" "app_tier" {
  name   = "${var.project_name}-sg-app"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_tier.id]
  }
}

resource "aws_security_group" "web_tier" {
  name   = "${var.project_name}-sg-web"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Lambda minimaliste de rotation des secrets (logique métier à compléter)
resource "aws_iam_role" "rotation_role" {
  name = "${var.project_name}-secrets-rotation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rotation_basic" {
  role       = aws_iam_role.rotation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "rotation_zip" {
  type        = "zip"
  output_path = "${path.module}/build/rotation.zip"
  source {
    content  = "def lambda_handler(event, context):\n    # Logique de rotation RDS (createSecret/setSecret/testSecret/finishSecret)\n    return {'status': 'ok'}\n"
    filename = "index.py"
  }
}

resource "aws_lambda_function" "rotation" {
  function_name = "${var.project_name}-secrets-rotation"
  role          = aws_iam_role.rotation_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.rotation_zip.output_path
  timeout       = 30
}

##############################################
# 4. Détection de menaces & conformité
##############################################
resource "aws_guardduty_detector" "this" {
  enable = true
}

resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.this]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

resource "aws_securityhub_standards_subscription" "pci" {
  depends_on    = [aws_securityhub_account.this]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/pci-dss/v/3.2.1"
}

##############################################
# 5. AWS Config - remédiation automatique
##############################################
resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config_role.arn
}

resource "aws_iam_role" "config_role" {
  name = "${var.project_name}-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "${var.project_name}-encrypted-volumes"
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_config_rule" "s3_encrypted" {
  name = "${var.project_name}-s3-encrypted"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder.this]
}

##############################################
# 6. WAF - protection edge du tier web
##############################################
resource "aws_wafv2_web_acl" "this" {
  name        = "${var.project_name}-waf"
  scope       = "REGIONAL"
  description = "Protection OWASP Top 10 pour le tier web"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-Managed-CommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "commonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }
}

##############################################
# 7. IAM - moindre privilège (SCP au niveau Org à appliquer séparément)
##############################################
resource "aws_iam_policy" "deny_root_actions" {
  name        = "${var.project_name}-deny-unencrypted-uploads"
  description = "Refuse la création d'objets S3 non chiffrés"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyUnEncryptedObjectUploads"
      Effect    = "Deny"
      Action    = "s3:PutObject"
      Resource  = "*"
      Condition = {
        StringNotEquals = {
          "s3:x-amz-server-side-encryption" = "aws:kms"
        }
      }
    }]
  })
}
