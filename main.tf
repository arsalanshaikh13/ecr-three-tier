##############################################
# PRODUCTION-GRADE ECS on EC2 with Auto Scaling
##############################################

#---------------------------------------------
# 1. ECR Repository (Immutable + Lifecycle)
#---------------------------------------------

resource "aws_ecr_repository" "app_repos" {
  name                 = "rusin-nextjs-app-repo-${local.env_suffix}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { 
    Name = "ecr-rusin-${local.env_suffix}" 
  })
}

resource "aws_ecr_lifecycle_policy" "app_repo_lifecycle" {
  # for_each   = aws_ecr_repository.app_repos
  # repository = each.value.name # References the name from the repo loop above
  repository = aws_ecr_repository.app_repos.name # References the name from the repo loop above

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}


#---------------------------------------------
# 2. CloudWatch Log Group
#---------------------------------------------
# resource "aws_cloudwatch_log_group" "ecs_log_group" {
#   name              = "/ecs/rusin-${local.env_suffix}"
#   retention_in_days = 30 
#   tags              = local.common_tags
# }
locals {
  ecr_names = toset(["app", "mongo"])
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  # Loops through dashboard, books, and authors
  for_each          = local.ecr_names 
  
  # Creates distinct names like /ecs/rusin-books-dev
  name              = "/ecs/rusin-${each.key}-${local.env_suffix}"
  retention_in_days = 30 
  
  tags = merge(local.common_tags, {
    Name = "rusin-${each.key}-logs-${local.env_suffix}"
  })
}
#---------------------------------------------
# 3. IAM Roles (Tasks, Execution, and EC2 Nodes)
#---------------------------------------------
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution Role (For the ECS Agent on the task)
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecsTaskExecutionRole-${local.env_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role (For Application Code)
resource "aws_iam_role" "ecs_task_role" {
  name               = "ecsTaskRole-${local.env_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}


# NEW: IAM Role & Profile for the underlying EC2 Instances
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
# asg instance profile iam role
resource "aws_iam_role" "ecs_node_role" {
  name               = "ecsNodeRole-${local.env_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Recommended Solution:
resource "aws_iam_role_policy_attachment" "ecs_node_role_ec2" {
  role       = aws_iam_role.ecs_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs_node_role_cognito" {
  role       = aws_iam_role.ecs_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonCognitoPowerUser"
}
resource "aws_iam_role_policy_attachment" "ecs_node_role_exec" {
  role       = aws_iam_role.ecs_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_node_role_cw" {
  role       = aws_iam_role.ecs_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess" # Note: Corrected standard policy ARN
}
resource "aws_iam_instance_profile" "ecs_node_profile" {
  name = "ecsNodeProfile-${local.env_suffix}"
  role = aws_iam_role.ecs_node_role.name
}

# Allow Execution role to read Secrets Manager
resource "aws_iam_policy" "ecs_task_secrets_policy" {
  name = "ecsTaskSecretsPolicy-${local.env_suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowReadingSecretsManager"
        Action   = ["secretsmanager:GetSecretValue",
                    "secretsmanager:PutSecretValue",
                    "secretsmanager:DescribeSecret"
                  ]
        Effect   = "Allow"
        Resource = [
                    aws_secretsmanager_secret.mongodb_root_password.arn,
                    aws_secretsmanager_secret.mongodb_uri.arn
                  ]
    },
    {
        Sid      = "AllowReadingSSMParameters"
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        # Ensure it can read your specific SSM Parameters
        Resource = [
          aws_ssm_parameter.better_auth_secret.arn,
          aws_ssm_parameter.cognito_client_id.arn,
          aws_ssm_parameter.cognito_client_secret.arn
        ]
      }
    
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_secrets_policy.arn
}



# 1. The Policy that allows your Node.js app to query ECS
resource "aws_iam_policy" "ecs_metadata_policy" {
  name        = "ECSMetadataAccessPolicy"
  description = "Allows the Express app to describe tasks and container instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeTasks",
          "ecs:DescribeContainerInstances"
        ]
        # Restrict this to your specific cluster for security
        Resource = [
          "arn:aws:ecs:${var.region}:${var.account_id}:task/${aws_ecs_cluster.app_cluster.name}/*",
          "arn:aws:ecs:${var.region}:${var.account_id}:container-instance/${aws_ecs_cluster.app_cluster.name}/*"
        ]
      }
    ]
  })
}

# 2. Attach it to your Task Role (Ensure your ecs_task_role exists!)
resource "aws_iam_role_policy_attachment" "ecs_metadata_attach" {
  role       = aws_iam_role.ecs_task_role.name 
  policy_arn = aws_iam_policy.ecs_metadata_policy.arn
}
resource "aws_iam_role_policy_attachment" "ecs_metadata_attach_exec" {
  # Change this to target the Execution Role, since that is what the log says your app is using!
  role       = aws_iam_role.ecs_task_execution_role.name 
  policy_arn = aws_iam_policy.ecs_metadata_policy.arn
}


#---------------------------------------------
# SSM Parameter and Secrets Manager setup
#---------------------------------------------


resource "aws_ssm_parameter" "better_auth_secret" {
  name        = "/nextjs-task-manager/prod/better-auth-secret"
  description = "Secret key for Next.js Better Auth"
  type        = "SecureString"
  value       = "REPLACE_ME_IN_CONSOLE"

  # lifecycle {
  #   ignore_changes = [value]
  # }
}
# 1. Cognito Client ID (Stored in SSM)
resource "aws_ssm_parameter" "cognito_client_id" {
  name        = "/nextjs-task-manager/prod/cognito-client-id"
  description = "AWS Cognito Client ID"
  type        = "SecureString"
  
  # Directly references the created Cognito Client
  value       = aws_cognito_user_pool_client.nextjs_client.id
}

# 2. Cognito Client Secret (Stored in SSM)
resource "aws_ssm_parameter" "cognito_client_secret" {
  name        = "/nextjs-task-manager/prod/cognito-client-secret"
  description = "AWS Cognito Client Secret"
  type        = "SecureString"
  
  # Directly references the generated secret
  value       = aws_cognito_user_pool_client.nextjs_client.client_secret
}

# MongoDB Root Password
# We generate a random, secure password for the database via Terraform
resource "random_password" "mongodb_password" {
  length  = 16
  special = false
}
resource "aws_secretsmanager_secret" "mongodb_root_password" {
  name        = "/nextjs-task-manager/prod/mongodb-root-password"
  description = "Root password for the MongoDB container"
  recovery_window_in_days = 0 
  tags = merge(local.common_tags, { Name = "${var.project_name}-mongo-password-secret" })


}
# Store just the password in Secrets Manager for the MongoDB container to usehttp
resource "aws_secretsmanager_secret_version" "mongodb_root_password_val" {
  secret_id     = aws_secretsmanager_secret.mongodb_root_password.id
  secret_string = random_password.mongodb_password.result
  #   lifecycle {
  #   ignore_changes = [secret_string]
  # }

}

# Construct the full URI and store it in Secrets Manager for the App container to use
# MongoDB Connection String (URI)
resource "aws_secretsmanager_secret" "mongodb_uri" {
  name        = "/nextjs-task-manager/prod/mongodb-uri"
  description = "Full connection string for the App to connect to MongoDB"
  recovery_window_in_days = 0 
  tags = merge(local.common_tags, { Name = "${var.project_name}-mongo-uri" })


}
resource "aws_secretsmanager_secret_version" "mongodb_uri_val" {
  secret_id     = aws_secretsmanager_secret.mongodb_uri.id
  
  # Dynamically builds: mongodb://admin:<random_password>@<internal-nlb-dns>:27017/task_manager?authSource=admin
  secret_string = format(
    "mongodb://admin:%s@%s:27017/task_manager?authSource=admin",
    random_password.mongodb_password.result,
    aws_lb.mongodb_internal.dns_name
  )

  # lifecycle {
  #   ignore_changes = [secret_string]
  # }
}


#---------------------------------------------
# 5. Security Groups
#---------------------------------------------

# security group for alb
resource "aws_security_group" "alb_sg" {
  name        = "alb security group"
  description = "enable http/https access on port 80/443"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "http access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "https access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "alb_sg"
  })
}



# NEW: Node SG (For the underlying EC2 instances to talk to AWS endpoints)
resource "aws_security_group" "ecs_node_sg" {
  name        = "ecs-node-sg-${local.env_suffix}"
  description = "SG for ECS EC2 nodes"
  vpc_id      = aws_vpc.vpc.id
  # ingress {
  #   description = "node port access"
  #   from_port   = 3200
  #   to_port     = 3200
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }
  # ingress {
  #   description = "node port access"
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

# Dynamically creates ingress rules for 3200, 3300, and 3400
  # dynamic "ingress" {
  #   for_each = local.services
  #   content {
  #     description     = "Access for ${ingress.key} from ALB"
  #     from_port       = ingress.value.port
  #     to_port         = ingress.value.port
  #     protocol        = "tcp"
  #     # Only allow traffic that comes through the Load Balancer
  #     security_groups = [aws_security_group.alb_sg.id] 
  #   }
  # }
  ingress {
    description = "node port access"
    from_port                = 32768
    to_port                  = 65535
    protocol                 = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#---------------------------------------------
# 6. EC2 Auto Scaling Group & Launch Template
#---------------------------------------------
# Dynamically fetch the latest Amazon Linux 2023 ECS-Optimized AMI
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "ecs-template-${local.env_suffix}"
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  # instance_type = "t3.medium"
  instance_type = "c7i-flex.large"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_node_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_node_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.app_cluster.name} >> /etc/ecs/ecs.config
  EOF
  )
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "ecs-asg-${local.env_suffix}"
  vpc_zone_identifier = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]
  # vpc_zone_identifier = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]
  
  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

#---------------------------------------------
# 7. ECS Cluster & Capacity Provider
#---------------------------------------------
resource "aws_ecs_cluster" "app_cluster" {
  name = "ecs-cluster-${local.env_suffix}"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.common_tags
}

resource "aws_ecs_capacity_provider" "ec2_provider" {
  name = "ec2-capacity-provider-${local.env_suffix}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100 
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_attach" {
  cluster_name = aws_ecs_cluster.app_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.ec2_provider.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ec2_provider.name
  }
}

#---------------------------------------------
# 8. AWS Cognito setup
#---------------------------------------------

# 1. The Cognito User Pool
# This is the core directory that holds your users.
resource "aws_cognito_user_pool" "main" {
  name = "nextjs-task-manager-pool"

  # Allow users to sign in with their email address instead of a standard username
  alias_attributes = ["email"]

  # Automatically verify the email address when a new user signs up
  auto_verified_attributes = ["email"]

  # Standard security password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # Customize the verification email sent to new users
  verification_message_template {
      email_message = "Welcome to the Task Manager! Your verification code is {####}."
      email_subject = "Verify your email address"
      default_email_option = "CONFIRM_WITH_CODE" 
  }

  # Optional: Keep the user pool lean by deleting users if you destroy the infrastructure
  lifecycle {
    prevent_destroy = false
  }
}

# 2. The Cognito User Pool Domain
# Required for the Hosted UI and OAuth 2.0 endpoints to function.
resource "aws_cognito_user_pool_domain" "main" {
  # IMPORTANT: This domain prefix must be globally unique across all of AWS.
  # You may need to change "task-app-auth-123" if it is already taken.
  domain       = "auth-devsandbox-space" 
  user_pool_id = aws_cognito_user_pool.main.id
}

# 3. The Cognito App Client
# Connects your Next.js application to the User Pool.
resource "aws_cognito_user_pool_client" "nextjs_client" {
  name         = "nextjs-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Required for server-side Next.js authentication (like NextAuth or Better Auth)
  generate_secret = true

  # Allowed Callback URLs
  callback_urls = [
    "https://devsandbox.space/api/auth/callback/cognito",
    "http://localhost:3000/api/auth/callback/cognito" # Kept for local dev testing
  ]

  # Allowed Sign-out URLs
  logout_urls = [
    "https://devsandbox.space/api/auth-logout",
    "http://localhost:3000/api/auth-logout" # Kept for local dev testing
  ]

  # OAuth 2.0 Settings
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"] # Authorization code grant
  allowed_oauth_scopes                 = ["openid", "email", "profile", "aws.cognito.signin.user.admin"]
  
  # Ensure the default Cognito provider is supported
  supported_identity_providers         = ["COGNITO"]
}


# Fetch the current AWS region automatically
# data "aws_region" "current" {}

# 1. Cognito User Pool ID
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

# 2. Cognito App Client ID
output "cognito_client_id" {
  description = "The ID of the Cognito App Client"
  value       = aws_cognito_user_pool_client.nextjs_client.id
}

# 3. Cognito App Client Secret
output "cognito_client_secret" {
  description = "The Secret of the Cognito App Client"
  value       = aws_cognito_user_pool_client.nextjs_client.client_secret
  sensitive   = true # Hides the value in the standard CLI output
}

# 4. Cognito Region
output "cognito_region" {
  description = "The AWS region where Cognito is deployed"
  # value       = data.aws_region.current.name
  value       = var.region
}

# 5. Cognito Domain (Fully Qualified URL)
output "cognito_domain_url" {
  description = "The full URL of the Cognito Hosted UI domain"
  # Constructs the standard AWS Cognito domain format required by most Auth libraries
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

#---------------------------------------------
# 8. Route 53 & ACM Certificate (HTTPS)
#---------------------------------------------
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "app_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  subject_alternative_names = ["*.${var.domain_name}"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "app_cert_wait" {
  certificate_arn         = aws_acm_certificate.app_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


# 1. Root Domain (devsandbox.space)
resource "aws_route53_record" "root_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}
# 2. Subdomains (www, books, authors)
resource "aws_route53_record" "subdomain_alias" {
  for_each = toset(["www"])
  
  # for_each = toset(["www", "books", "authors"])
  
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}


#---------------------------------------------
# 9. ALB + Target Group + Listener
#---------------------------------------------
# resource "aws_lb" "app_alb" {
#   name               = "alb-${local.env_suffix}"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb_sg.id]
#   subnets            = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]
#   # subnets            = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]
#   # enable_deletion_protection = true 
# }


# resource "aws_lb_target_group" "app_tg" {
#   for_each    = toset(["books", "authors", "dashboard"])
#   name        = "${each.key}-tg-${local.env_suffix}"
#   # name_prefix        = "${each.key}-tg-${local.env_suffix}"
#   # name        = "tg-${local.env_suffix}"

#   # 2. ADD 'name_prefix' (Must be 6 characters or less)
#   # alway use name_prefix when we have to create and destroy the same resource
#   # name_prefix          = "tg-${local.env_suffix}"
#   # port        = 3200
#   port        = 222
#   # port        = 80
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.vpc.id
#   # target_type = "ip" # Must be 'ip' when using awsvpc network mode
#   target_type = "instance" # Must be 'instance' when using host/bridge network mode

#   # ADD THIS LINE: Lower the wait time from 5 minutes to 30 seconds
#   deregistration_delay = 30

#   health_check {
#     path                = "/health"
#     healthy_threshold   = 5
#     unhealthy_threshold = 3
#     timeout             = 15
#     interval            = 30
#     matcher             = "200-399"
#   }
#   # 3. ADD THIS LIFECYCLE BLOCK
#   lifecycle {
#     create_before_destroy = true
#   }
# }



# # Redirect HTTP to HTTPS
# resource "aws_lb_listener" "http_redirect" {
#   load_balancer_arn = aws_lb.app_alb.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type = "redirect"
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }
# }

# # Secure HTTPS Listener
# resource "aws_lb_listener" "app_listener_https_secure" {
#   load_balancer_arn = aws_lb.app_alb.arn
#   port              = 443
#   protocol          = "HTTPS"
#   certificate_arn   = aws_acm_certificate_validation.app_cert_wait.certificate_arn

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg["dashboard"].arn
#   }
# }
# resource "aws_lb_listener_rule" "api_routing" {
#   # Loop only through authors and books
#   for_each     = setsubtract(toset(["books", "authors", "dashboard"]), ["dashboard"])
#   listener_arn = aws_lb_listener.app_listener_https_secure.arn
#   priority     = each.key == "books" ? 10 : 20

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg[each.key].arn
#   }

#   condition {
#     host_header {
#       values = ["${each.key}.${var.domain_name}"]
#     }
#   }
#   # # Condition 1: Match the specific domain (Optional but recommended)
#   # condition {
#   #   host_header {
#   #     values = ["www.${var.domain_name}", var.domain_name]
#   #   }
#   # }

#   # # Condition 2: Match the path
#   # condition {
#   #   path_pattern {
#   #     # Matches exactly "/books" and anything under it like "/books/123"
#   #     values = ["/${each.key}", "/${each.key}/*", "/${each.key}*"] 
#   #   }
#   # }
# }
#---------------------------------------------
# 10. ECS Task Definition
#---------------------------------------------
# resource "aws_ecs_task_definition" "app_task" {
#   for_each                 = toset(["books", "authors", "dashboard"])
#   family                   = "rusin-task-${local.env_suffix}"
#   # network_mode             = "host"
#   # network_mode             = "bridge"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["EC2"] # Changed from FARGATE
#   cpu                      = var.app_cpu
#   memory                   = var.app_memory
#   memoryReservation        = var.app_memory_soft_limit
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn 

#   container_definitions = jsonencode([
#     {
#       name      = "rusin"
#       # image     = "${aws_ecr_repository.app_repo.repository_url}:latest" 
#       image     = "httpd:2.4-alpine" # Bootstrapping image
#       essential = true

#       portMappings = [{
#         containerPort = 3200
#         protocol      = "tcp"
#       }]

      
#       # Only the dashboard gets these variables
#       environment = each.key == "dashboard" ? [
#         {
#           name  = "BOOKS_API_URL"
#           value = "http://books.${var.domain_name}"
#         },
#         {
#           name  = "AUTHORS_API_URL"
#           value = "http://authors.${var.domain_name}"
#         }
#       ] : [] # Returns an empty list for books and authors


#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
#           awslogs-region        = var.region
#           awslogs-stream-prefix = "ecs"
#         }
#       }
#     }
#   ])
# }


# resource "aws_ecs_task_definition" "app_task" {
  # for_each = {
  #   books     = { port = 3300 }
  #   authors   = { port = 3400 }
  #   dashboard = { port = 3200 }
  # }
#   for_each         = local.services
#   family                   = "rusin-task-${each.key}"
#   # network_mode             = "awsvpc"
#   network_mode             = "bridge"
#   # network_mode             = "host"
#   requires_compatibilities = ["EC2"]
#   cpu                      = var.app_cpu
#   memory                   = var.app_memory
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn

#   # This reads your JSON file and injects the variables
#   container_definitions = templatefile("${path.module}/task-definition.json.template", {
#     SERVICE_NAME     = each.key
#     APP_PORT         = each.value.port
#     # ACCOUNT_ID       = data.aws_caller_identity.current.account_id
#     ACCOUNT_ID       = var.account_id
#     APP_CPU          = var.app_cpu
#     APP_MEMORY       = var.app_memory
#     ENV_VAR          = local.env_suffix
#     # Initial bootstrap env; CI/CD will handle the real ones later
#     ENVIRONMENT_VARS = each.key == "dashboard" ? jsonencode([
#       { name = "BOOKS_SERVICE_URL", value = "https://books.${var.domain_name}" },
#       { name = "AUTHORS_SERVICE_URL", value = "https://authors.${var.domain_name}" }
#       # { name = "AUTHORS_SERVICE_URL", valueFrom = aws_secretsmanager_secret.app_secret.arn }
#     ]) : "[]"
#   })
  
#     lifecycle {
#     ignore_changes = [
#       container_definitions
      
#     ]
#   }

# }

resource "aws_ecs_task_definition" "mongodb" {
  family                   = "nextjs-task-manager-mongodb"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  # Provisions a local Docker volume on the EC2 host's EBS drive
  volume {
    name = "mongodb_data_prod"
    docker_volume_configuration {
      scope         = "shared"
      autoprovision = true
      driver        = "local"
    }
  }
  volume {
    name = "mongodb_config_prod"
    docker_volume_configuration {
      scope         = "shared"
      autoprovision = true
      driver        = "local"
    }
  }

  container_definitions = jsonencode([
    {
      name      = "nextjs_task_manager_mongodb"
      image     = "mongo:7.0"
      # image     = var.mongo_image_uri
      essential = true
      
      # Resource limits moved to the container level to prevent host OOM issues
      memory    = var.mongo_memory 
      cpu       = var.mongo_cpu
      
      portMappings = [
        {
          containerPort = 27017
          hostPort      = 27017
          protocol      = "tcp"
        }
      ]
      
      environment = [
        { name = "MONGO_INITDB_ROOT_USERNAME", value = "admin" },
        { name = "MONGO_INITDB_DATABASE", value = "task_manager" }
      ]
      
      secrets = [
        { name = "MONGO_INITDB_ROOT_PASSWORD", valueFrom = aws_secretsmanager_secret.mongodb_root_password.arn }
      ]

      mountPoints = [
        {
          sourceVolume  = "mongodb_data_prod"
          containerPath = "/data/db"
          readOnly      = false
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "echo 'db.runCommand(\"ping\").ok' | mongosh localhost:27017/test --quiet"]
        interval    = 10
        timeout     = 5
        retries     = 5
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/rusin-mongo-${local.env_suffix}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group": "true",
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "app" {
  family                   = "nextjs-task-manager-app"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "nextjs_task_manager_app"
      image     = var.app_image_uri
      essential = true
      memory    = var.app_memory
      cpu       = var.app_cpu
      
      portMappings = [
        {
          containerPort = 3000
          # hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NODE_ENV", value = local.env_suffix },
        { name = "NEXT_PUBLIC_APP_URL", value = "https://${var.domain_name}" },
        { name = "BETTER_AUTH_URL", value = "https://${var.domain_name}" },
        { name = "COGNITO_DOMAIN", value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com" },
        { name = "COGNITO_REGION", value = var.region },
        { name = "COGNITO_USER_POOL_ID", value = aws_cognito_user_pool.main.id }
      ]

      secrets = [
        { name = "BETTER_AUTH_SECRET", valueFrom = aws_ssm_parameter.better_auth_secret.arn },
        { name = "MONGODB_URI", valueFrom = aws_secretsmanager_secret.mongodb_uri.arn },
        { name = "COGNITO_CLIENT_ID", valueFrom = aws_ssm_parameter.cognito_client_id.arn },
        { name = "COGNITO_CLIENT_SECRET", valueFrom = aws_ssm_parameter.cognito_client_secret.arn }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3000 || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 40
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          # "awslogs-group"         = "/aws/ec2/nextjs-task-manager-app"
          "awslogs-group"         = "/ecs/rusin-app-${local.env_suffix}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group": "true"
        }
      }
    }
  ])
}
#---------------------------------------------
# 11. ECS Service
#---------------------------------------------
# resource "aws_ecs_service" "app_service" {
#   name             = "rusin-service-${local.env_suffix}"
#   cluster          = aws_ecs_cluster.app_cluster.id
#   task_definition  = aws_ecs_task_definition.app_task.arn
#   desired_count    = var.desired_count

#   # ADD THIS: Force Terraform to give up faster if AWS hangs
#   timeouts {
#     delete = "5m" 
#   }
#   # Removed launch_type = "FARGATE", replaced with Capacity Provider Strategy
#   capacity_provider_strategy {
#     capacity_provider = aws_ecs_capacity_provider.ec2_provider.name
#     weight            = 100
#   }

#   # this only works for awsvpc network mode not host network mode
#   network_configuration {
#     # subnets          = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id] 
#     subnets          = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id] 
#     security_groups  = [aws_security_group.app_task_sg.id]
#     assign_public_ip = false 
#     # assign_public_ip = true # it only works with fargate
#   }

#   # ADD THIS LINE: Give the container 60 seconds to boot before the ALB checks it
#   health_check_grace_period_seconds = 60

#   load_balancer {
#     target_group_arn = aws_lb_target_group.app_tg.arn
#     container_name   = "rusin"
#     container_port   = 3200
#   }

#   deployment_minimum_healthy_percent = 100 
#   deployment_maximum_percent         = 200

#   lifecycle {
#     ignore_changes = [
#       task_definition,
#       desired_count
#     ]
#   }

#   depends_on = [
#     aws_lb_listener.app_listener_https_secure,
#     aws_ecs_cluster_capacity_providers.cluster_attach # Ensure CP is attached before Service uses it
#   ]
# }


# resource "aws_ecs_service" "app_service" {
#   for_each         = local.services
#   name             = "${each.key}-service-${local.env_suffix}"
#   cluster          = aws_ecs_cluster.app_cluster.id
#   # References the specific task definition created for this service
#   task_definition  = aws_ecs_task_definition.app_task[each.key].arn
#   desired_count    = var.desired_count

#   timeouts {
#     delete = "5m" 
#   }

#   capacity_provider_strategy {
#     capacity_provider = aws_ecs_capacity_provider.ec2_provider.name
#     weight            = 100
#   }


#   health_check_grace_period_seconds = 60

#   load_balancer {
#     # Assuming your target groups are named similarly: dashboard-tg, books-tg, etc.
#     target_group_arn = aws_lb_target_group.app_tg[each.key].arn
#     container_name   = "rusin-${each.key}" # Matches the name in your JSON template
#     container_port   = each.value.port
#   }

#   deployment_minimum_healthy_percent = 100 
#   deployment_maximum_percent         = 200

#   lifecycle {
#     ignore_changes = [
#       task_definition,
#       desired_count
#     ]
#   }

#   depends_on = [
#     aws_lb_listener.app_listener_https_secure,
#     aws_ecs_cluster_capacity_providers.cluster_attach
#   ]
# }



# The Internal Network Load Balancer
resource "aws_lb" "mongodb_internal" {
  name               = "mongodb-internal-nlb"
  internal           = true
  load_balancer_type = "network"
  
  # Deploy this in your private subnets
  # subnets            = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]
  subnets            = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]

  # AWS recently added Security Group support for NLBs. 
  # This ensures only your App tier can talk to the database tier.
  security_groups    = [aws_security_group.mongodb_nlb.id]
}

# The TCP Listener
resource "aws_lb_listener" "mongodb" {
  load_balancer_arn = aws_lb.mongodb_internal.arn
  port              = "27017"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    # This references the target group we created in the previous step
    target_group_arn = aws_lb_target_group.mongodb_internal.arn 
  }
}

# mongo db and internal alb terraform
# The Target Group for the Internal NLB (TCP Traffic)
resource "aws_lb_target_group" "mongodb_internal" {
  name     = "mongodb-internal-tg"
  port     = 27017
  protocol = "TCP" # Crucial for MongoDB
  vpc_id   = aws_vpc.vpc.id
  # target_type = "ip" # Must be 'ip' when using awsvpc network mode
  target_type = "instance" # Must be 'instance' when using host/bridge network mode

  # ADD THIS LINE: Lower the wait time from 5 minutes to 30 seconds
  deregistration_delay = 30

  # Health check using TCP to ensure the port is open
  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }
}

# Security Group for the Internal NLB
resource "aws_security_group" "mongodb_nlb" {
  name        = "mongodb-nlb-sg"
  description = "Allow App tier to reach MongoDB NLB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "MongoDB from App Tier"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    # Only allow traffic originating from the Next.js App's Security Group
    security_groups = [aws_security_group.ecs_node_sg.id] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Add an Ingress rule to your EC2 Host Security Group 
# to allow the NLB to forward traffic to the containers
resource "aws_security_group_rule" "ec2_mongodb_ingress" {
  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_node_sg.id
  source_security_group_id = aws_security_group.mongodb_nlb.id
}
# The MongoDB ECS Service
resource "aws_ecs_service" "mongodb" {
  name            = "mongodb-service"
  cluster         = aws_ecs_cluster.app_cluster.id # Replace with your cluster ID
  task_definition = aws_ecs_task_definition.mongodb.arn
  desired_count   = var.desired_count
  # launch_type     = "EC2"

  # Attach the service to the NLB Target Group
  load_balancer {
    target_group_arn = aws_lb_target_group.mongodb_internal.arn
    container_name   = "nextjs_task_manager_mongodb"
    container_port   = 27017
  }


  timeouts {
    delete = "5m" 
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_provider.name
    weight            = 100
  }

  health_check_grace_period_seconds = 60


  deployment_minimum_healthy_percent = 100 
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count
    ]
  }

  depends_on = [
    aws_lb_listener.mongodb,
    aws_ecs_cluster_capacity_providers.cluster_attach
  ]

  # Ensure the tasks are distributed across your EC2 instances (if running multiple)
  placement_constraints {
    type       = "distinctInstance"
  }
}

resource "aws_lb" "app_alb" {
  name               = "alb-${local.env_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]
  # subnets            = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]
  # enable_deletion_protection = true 
}





# Redirect HTTP to HTTPS
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Secure HTTPS Listener
resource "aws_lb_listener" "app_listener_https_secure" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.app_cert_wait.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_external.arn
  }
}
#################
# The Target Group for the External ALB (HTTP Traffic)
resource "aws_lb_target_group" "app_external" {
  name     = "nextjs-app-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
    # target_type = "ip" # Must be 'ip' when using awsvpc network mode
  target_type = "instance" # Must be 'instance' when using host/bridge network mode
  # ADD THIS LINE: Lower the wait time from 5 minutes to 30 seconds
  deregistration_delay = 30

  # stickiness {
  #   type            = "lb_cookie"
  #   cookie_duration = 86400 # How long the stickiness lasts (in seconds). 86400 = 1 day.
  #   enabled         = true
  # }
  health_check {
    path                = "/api/health" # Or a dedicated /api/health route
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 3
    timeout             = 15
    interval            = 30
    matcher             = "200-399"
  }
}

# The Next.js App ECS Service
resource "aws_ecs_service" "app" {
  name            = "nextjs-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id # Replace with your cluster ID
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2 # Assuming you want high availability
  # launch_type     = "EC2"

  # Attach the service to the ALB Target Group
  load_balancer {
    target_group_arn = aws_lb_target_group.app_external.arn
    container_name   = "nextjs_task_manager_app"
    container_port   = 3000
  }

  timeouts {
    delete = "5m" 
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_provider.name
    weight            = 100
  }


  health_check_grace_period_seconds = 60

  
  deployment_minimum_healthy_percent = 100 
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count
    ]
  }

  depends_on = [
    aws_lb_listener.app_listener_https_secure,
    aws_ecs_cluster_capacity_providers.cluster_attach
  ]

  # Optional: Spread tasks evenly across Availability Zones
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
}
#---------------------------------------------
# 12. Application Auto Scaling (Task Level)
#---------------------------------------------
# no need to scale mongo db container
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.app_cluster.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto-scale tasks based on CPU Utilization
resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "rusin-cpu-autoscaling-${local.env_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
