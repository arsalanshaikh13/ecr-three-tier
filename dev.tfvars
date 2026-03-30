##############################################
# Dev Environment Variables
##############################################

region       = "us-east-1"
environment  = "dev"
project_name = "ECS-Rusin-ALB"

# Networking
vpc_id          = "vpc-id"
public_subnets  = ["subnet-id1", "subnet-id2"]
vpc_cidr        = "10.0.0.0/16"
pub_sub_1a_cidr = "10.0.1.0/24"
pub_sub_2b_cidr = "10.0.2.0/24"
pri_sub_3a_cidr = "10.0.3.0/24"
pri_sub_4b_cidr = "10.0.4.0/24"
#private_subnets = ["subnet-ccc333", "subnet-ddd444"]

# Security Groups
alb_sg_id = "sg-id1"
app_sg_id = "sg-id2"

# ECS Configuration
# ECS task sizing
# 256 CPU units = 0.25 vCPU
# 512 MiB       = 0.5 GB
# Smallest valid Fargate size
app_cpu       = 512 # 0.5 vCPU
app_memory    = 1024 # 1 GB
image_tag     = "latest"
desired_count = 1

db_cpu = 1024
db_memory = 2048
db_name = "lirwEcrDB"
# db_password = "secret_password"
db_username = "admin123"

# Secret (use ARN of secret in AWS Secrets Manager)
secret_key     = "Secret Key"
better_auth_secret = "eE0n2KuKkUnDkOWAandcOV8unOrISebs"
app_secret_arn = "arn:aws:secretsmanager:us-east-1:ACCOUNT-ID:secret:APP_SECRET-3vRpHC"