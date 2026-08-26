variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "project_name" {
  type    = string
  default = "secure-3tier"
}

variable "vpc_cidr" {
  type    = string
  default = "10.50.0.0/16"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "compliance_standards" {
  description = "Référentiels de conformité à activer dans Security Hub"
  type        = list(string)
  default     = ["cis-aws-foundations-benchmark", "pci-dss"]
}
