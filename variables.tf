##############################################
# Variables
##############################################

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, stage, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for ECS and ALB resources"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

# variable "alb_sg_id" {
#   description = "Security group ID for ALB"
#   type        = string
# }

# variable "app_sg_id" {
#   description = "Security group ID for ECS tasks"
#   type        = string
# }

variable "app_cpu" {
  description = "CPU units for the ECS task definition"
  type        = number
  default     = 512
}

variable "app_memory" {
  description = "Memory in MB for the ECS task definition"
  type        = number
  default     = 1024
}
variable "db_cpu" {
  description = "CPU units for the ECS task definition"
  type        = number
  default     = 1024
}

variable "db_memory" {
  description = "Memory in MB for the ECS task definition"
  type        = number
  default     = 2048
}
variable "db_username" {
  description = "Memory in MB for the ECS task definition"
  type        = string
  default     = "admin-123"
}
variable "db_name" {
  description = "Memory in MB for the ECS task definition"
  type        = string
  default     = "lirw-ecr-db"
}
# variable "db_password" {
#   description = "Memory in MB for the ECS task definition"
#   type        = string
#   sensitive = true
# }

variable "app_memory_soft_limit" {
  description = "Memory in MB for the ECS task definition"
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Image tag to deploy from ECR"
  type        = string
  default     = "latest"
}

# variable "app_secret_arn" {
#   description = "ARN of the AWS Secrets Manager secret for environment variables"
#   type        = string
#   sensitive   = true
# }
variable "secret_key" {
  description = "secret key value"
  type        = string
  sensitive   = true
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "domain_name" {
  description = "The primary domain name for the application (e.g., example.com)"
  type        = string
  default = "devsandbox.space"
}
variable "account_id" {
  description = "The primary account id"
  type        = string
  default = "750702272407"
}
variable "app_image_uri" {
  description = "The primary placeholder image"
  type        = string
  default = "node:24-alpine"
}
variable "mongo_image_uri" {
  description = "The primary placeholder image"
  type        = string
  default = "public.ecr.aws/docker/library/mongo:7.0-jammy"
}
variable "better_auth_secret" {
  description = "The primary placeholder image"
  type        = string
  sensitive = true
}

variable "project_name" {}
variable "vpc_cidr" {}
variable "pub_sub_1a_cidr" {}
variable "pub_sub_2b_cidr" {}
variable "pri_sub_3a_cidr" {}
variable "pri_sub_4b_cidr" {}
# variable "pri_sub_5a_cidr" {}
# variable "pri_sub_6b_cidr" {}
# variable "pri_sub_7a_cidr" {}
# variable "pri_sub_8b_cidr" {}