##############################################
# PRODUCTION-GRADE ECS on EC2 with Auto Scaling
##############################################

#---------------------------------------------
# 1. ECR Repository (Immutable + Lifecycle)
#---------------------------------------------
locals {
  ecr_names = toset(["frontend", "backend", "database-seeder"])
}

resource "aws_ecr_repository" "app_repos" {
  for_each = local.ecr_names
  name                 = "lirw-ecr-${each.key}-repo-${local.env_suffix}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { 
    Name = "ecr-lirwEcr-${each.key}-repo-${local.env_suffix}" 
  })
}
resource "aws_ecr_repository" "db_repo" {
  name                 = "lirw-ecr-database-seed-repo-${local.env_suffix}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { 
    Name = "ecr-lirwEcr--db-repo-${local.env_suffix}" 
  })
}

resource "aws_ecr_lifecycle_policy" "app_repo_lifecycle" {
    for_each = local.ecr_names

  # repository = each.value.name # References the name from the repo loop above
  repository = aws_ecr_repository.app_repos[each.key].name # References the name from the repo loop above

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
#   name              = "/ecs/lirwEcr-${local.env_suffix}"
#   retention_in_days = 30 
#   tags              = local.common_tags
# }
# locals {
#   ecr_names = toset(["frontend", "backend"])
# }

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  # Loops through dashboard, books, and authors
  for_each          = local.ecr_names 
  
  # Creates distinct names like /ecs/lirwEcr-books-dev
  name              = "/ecs/lirwEcr-${each.key}-${local.env_suffix}"
  retention_in_days = 30 
  
  tags = merge(local.common_tags, {
    Name = "lirwEcr-${each.key}-logs-${local.env_suffix}"
  })
}

# 1. Create a dedicated Log Group for your terminal sessions
resource "aws_cloudwatch_log_group" "ecs_exec_logs" {
  name              = "/ecs/execute-command/lirw-cluster"
  retention_in_days = 7
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
                    aws_secretsmanager_secret.rdsdb_root_password.arn
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
          aws_ssm_parameter.rds_db_address.arn,

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



# 2. Create the policy that allows the container to open a terminal
resource "aws_iam_policy" "ecs_exec_policy" {
  name = "lirw-ecs-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs_exec_logs.arn}:*"
      }
    ]
  })
}

# 3. Attach the policy to your EXISTING Next.js Task Role
# WARNING: Make sure this is your TASK role, not your EXECUTION role!
resource "aws_iam_role_policy_attachment" "ecs_exec_attachment" {
  role       = aws_iam_role.ecs_task_role.name # Change this if your role has a different name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}
#---------------------------------------------
# SSM Parameter and Secrets Manager setup
#---------------------------------------------


resource "aws_ssm_parameter" "rds_db_address" {
  name        = "/lirw-ecr/dev/rds_db_address"
  description = "database dns address"
  type        = "SecureString"
  value       = aws_db_instance.mysql_db.address

  # lifecycle {
  #   ignore_changes = [value]
  # }
}
output "db_address" {
  value = aws_db_instance.mysql_db.address
}


# MongoDB Root Password
# We generate a random, secure password for the database via Terraform
resource "random_password" "db_password" {
  length  = 16
  special = false
}
resource "aws_secretsmanager_secret" "rdsdb_root_password" {
  name        = "/lirw-ecr/dev/rds-root-password"
  description = "Root password for the rds container"
  recovery_window_in_days = 0 
  tags = merge(local.common_tags, { Name = "${var.project_name}-rdsdb-password-secret" })


}
# Store just the password in Secrets Manager for the MongoDB container to usehttp
resource "aws_secretsmanager_secret_version" "rdsdb_root_password_val" {
  secret_id     = aws_secretsmanager_secret.rdsdb_root_password.id
  secret_string = random_password.db_password.result
  #   lifecycle {
  #   ignore_changes = [secret_string]
  # }

}

# Construct the full URI and store it in Secrets Manager for the App container to use
# MongoDB Connection String (URI)
# resource "aws_secretsmanager_secret" "mongodb_uri" {
#   name        = "/nextjs-task-manager/prod/mongodb-uri"
#   description = "Full connection string for the App to connect to MongoDB"
#   recovery_window_in_days = 0 
#   tags = merge(local.common_tags, { Name = "${var.project_name}-mongo-uri" })


# }
# resource "aws_secretsmanager_secret_version" "mongodb_uri_val" {
#   secret_id     = aws_secretsmanager_secret.mongodb_uri.id
  
#   # Dynamically builds: mongodb://admin:<random_password>@<internal-nlb-dns>:27017/task_manager?authSource=admin
#   secret_string = format(
#     "mongodb://admin:%s@%s:27017/task_manager?authSource=admin&directConnection=true",
#     random_password.mongodb_password.result,
#     aws_lb.mongodb_internal.dns_name
#   )

#   # lifecycle {
#   #   ignore_changes = [secret_string]
#   # }
# }


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

resource "aws_security_group" "internal_alb_sg" {
  name        = "internal alb security group"
  description = "enable http/https access on port 80/443"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "http access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_node_frontend_sg.id]
  }

  # ingress {
  #   description = "http access"
  #   from_port   = 3200
  #   to_port     = 3200
  #   protocol    = "tcp"
  #   security_groups = [aws_security_group.ecs_node_frontend_sg.id]
  # }


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
resource "aws_security_group" "ecs_node_frontend_sg" {
  name        = "ecs-node-frontend-sg-${local.env_suffix}"
  description = "SG for ECS EC2 nodes frontend"
  vpc_id      = aws_vpc.vpc.id
  
  ingress {
    description = "node port access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

# 1. Existing Rule: Allow Public ALB to hit Ephemeral Ports
  # ingress {
  #   description     = "node port access from ALB"
  #   from_port       = 32768
  #   to_port         = 65535
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.alb_sg.id]
  # }
  # ingress {
  #   description     = "node port access from ALB"
  #   from_port       = 3000
  #   to_port         = 3000
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.alb_sg.id]
  # }

  # 2. NEW: Allow the Internal NLB to route traffic to the Mongo Container
  # ingress {
  #   description     = "Allow traffic from Internal NLB"
  #   from_port       = 27017
  #   to_port         = 27017
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.mongodb_nlb.id]
  # }

  # # 3. NEW: The Hairpin Fix (Self-Referencing)
  # # Allows containers on the same EC2 node to talk to each other
  # ingress {
  #   description = "Mongo ingress via NLB Client IP Preservation (Hairpin)"
  #   from_port   = 27017
  #   to_port     = 27017
  #   protocol    = "tcp"
  #   self        = true # This tells the SG to allow traffic from itself!
  # }

# Bulletproof Internal VPC Rule for MongoDB
  # ingress {
  #   description = "Allow all internal VPC traffic to hit MongoDB"
  #   from_port   = 27017
  #   to_port     = 27017
  #   protocol    = "tcp"
  #   # Replace with your actual VPC CIDR if it is different!
  #   cidr_blocks = ["10.0.0.0/16"] 
  # }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_node_backend_sg" {
  name        = "ecs-node-backend-sg-${local.env_suffix}"
  description = "SG for ECS EC2 nodes backend"
  vpc_id      = aws_vpc.vpc.id
  
    # 2. NEW: Allow the Internal NLB to route traffic to the Mongo Container

  ingress {
    description = "node port access"
    from_port   = 3200
    to_port     = 3200
    protocol    = "tcp"
    security_groups = [aws_security_group.internal_alb_sg.id]
  }


  # # 3. NEW: The Hairpin Fix (Self-Referencing)
  # # Allows containers on the same EC2 node to talk to each other
  # ingress {
  #   description = "Mongo ingress via NLB Client IP Preservation (Hairpin)"
  #   from_port   = 27017
  #   to_port     = 27017
  #   protocol    = "tcp"
  #   self        = true # This tells the SG to allow traffic from itself!
  # }

# Bulletproof Internal VPC Rule for MongoDB
  # ingress {
  #   description = "Allow all internal VPC traffic to hit MongoDB"
  #   from_port   = 27017
  #   to_port     = 27017
  #   protocol    = "tcp"
  #   # Replace with your actual VPC CIDR if it is different!
  #   cidr_blocks = ["10.0.0.0/16"] 
  # }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_node_rds_sg" {
  name        = "ecs-node-sg-${local.env_suffix}"
  description = "SG for ECS EC2 nodes rds"
  vpc_id      = aws_vpc.vpc.id
  
    # 2. NEW: Allow the Internal NLB to route traffic to the Mongo Container

  ingress {
    description = "node port access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_node_backend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# resource "aws_security_group" "ecs_node_sg" {
#   name        = "ecs-node-sg-${local.env_suffix}"
#   description = "SG for ECS EC2 nodes"
#   vpc_id      = aws_vpc.vpc.id

#   # 1. Existing Rule: Allow Public ALB to hit Ephemeral Ports
#   ingress {
#     description     = "node port access from ALB"
#     from_port       = 32768
#     to_port         = 65535
#     protocol        = "tcp"
#     security_groups = [aws_security_group.alb_sg.id]
#   }

#   # 2. NEW: Allow the Internal NLB to route traffic to the Mongo Container
#   ingress {
#     description     = "Allow traffic from Internal NLB"
#     from_port       = 27017
#     to_port         = 27017
#     protocol        = "tcp"
#     security_groups = [aws_security_group.mongodb_nlb.id]
#   }

#   # 3. NEW: The Hairpin Fix (Self-Referencing)
#   # Allows containers on the same EC2 node to talk to each other
#   ingress {
#     description = "Mongo ingress via NLB Client IP Preservation (Hairpin)"
#     from_port   = 27017
#     to_port     = 27017
#     protocol    = "tcp"
#     self        = true # This tells the SG to allow traffic from itself!
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
#---------------------------------------------
# 6. RDS setup
#---------------------------------------------


resource "aws_db_subnet_group" "main" {
  name       = "rds-subnet-group-${local.env_suffix}"
  subnet_ids = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]

  tags = {
    Name = "Main DB Subnet Group"
  }
}
resource "aws_db_instance" "mysql_db" {
  identifier           = "app-db-${local.env_suffix}"
  allocated_storage    = 20
  storage_type         = "gp3"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro" # Burstable instance for dev
  
  db_name              = var.db_name
  username             = var.db_username
  password             = random_password.db_password.result
  
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.ecs_node_rds_sg.id]
  
  parameter_group_name = "default.mysql8.0"
  publicly_accessible  = false
  skip_final_snapshot  = true
}

# Output the endpoint so you can pass it to your seeder task
output "rds_endpoint" {
  value = aws_db_instance.mysql_db.endpoint
}




resource "aws_ecs_task_definition" "db_seeder" {
  family                   = "db-seeder-${local.env_suffix}"
  requires_compatibilities = ["EC2"]
  network_mode             = "host" # Required for security group assignment
  cpu                      = var.db_cpu
  memory                   = var.db_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn 


  container_definitions = jsonencode([
    {
      name      = "mysql-seeder"
      image     = "alpine/mysql:seeder-latest" # Replace with your seeder image tag
      essential = true
      
      environment = [
        # { name = "DB_HOST", value = aws_db_instance.mysql_db.address },
        { name = "DB_DATABASE", value = aws_db_instance.mysql_db.db_name },
        { name = "DB_USER", value = aws_db_instance.mysql_db.username }
      ]

      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.rdsdb_root_password.arn },
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.rds_db_address.arn }
      ]

      # switch to camel case for jsonencode from snake_case otherwise cloudwatch log doesn't get created
      # Changed to camelCase for AWS API compatibility
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/lirwEcr-database-seeder-${local.env_suffix}"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "seeder"
        }
      }
    }
  ])
}

# Create the log group so you can see the seeding output
# resource "aws_cloudwatch_log_group" "seeder_logs" {
#   name              = "/ecs/db-seeder-${local.env_suffix}"
#   retention_in_days = 7
# }

# resource "terraform_data" "db_migration" {
#   # This triggers only when the task definition ARN changes
#   triggers_replace = [aws_ecs_task_definition.db_seeder.arn]
# # This ensures the seeder runs AFTER the DB and Task Definition are ready
#   depends_on = [aws_db_instance.mysql_db, aws_ecs_task_definition.db_seeder]
#   provisioner "local-exec" {
#     command = <<EOT
#       aws ecs run-task \
#         --cluster ${aws_ecs_cluster.app_cluster.name} \
#         --task-definition ${aws_ecs_task_definition.db_seeder.name} \
#         --launch-type EC2 \
#         --network-configuration 'awsvpcConfiguration={subnets=["${aws_subnet.pri_sub_3a.id}"],securityGroups=["${aws_security_group.ecs_node_backend_sg.id}"]}'
#     EOT
#   }
# }
#---------------------------------------------
# 6. EC2 Auto Scaling Group & Launch Template
#---------------------------------------------
# Dynamically fetch the latest Amazon Linux 2023 ECS-Optimized AMI
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

locals {
  ecs_apps = {
    frontend = {
      instance_type = "c7i-flex.large"
      subnets       = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]
      sg_id         = aws_security_group.ecs_node_frontend_sg.id
    }
    backend = {
      instance_type = "c7i-flex.large"
      subnets       = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]
      # subnets       = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]
      sg_id         = aws_security_group.ecs_node_backend_sg.id
    }
  }
}

resource "aws_launch_template" "ecs_lt" {
  for_each = local.ecs_apps

  name_prefix   = "ecs-${each.key}-template-"
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = each.value.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_node_profile.name
  }

  # This now dynamically picks the correct SG
  vpc_security_group_ids = [each.value.sg_id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.app_cluster.name} >> /etc/ecs/ecs.config
  EOF
  )
}

resource "aws_autoscaling_group" "ecs_asg" {
  for_each = local.ecs_apps

  name                = "ecs-asg-${each.key}-${local.env_suffix}"
  vpc_zone_identifier = each.value.subnets
  
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.ecs_lt[each.key].id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "ecs-node-${each.key}"
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
  configuration {
    execute_command_configuration {
      logging = "OVERRIDE" 
      log_configuration {
        # Set to false unless you also create and attach an aws_kms_key
        cloud_watch_encryption_enabled = false 
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec_logs.name
      }
    }
  }
  tags = local.common_tags
}

resource "aws_ecs_capacity_provider" "ec2_provider" {
  for_each = local.ecs_apps
  name = "ec2-capacity-provider-${each.key}-${local.env_suffix}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg[each.key].arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100 
    }
  }
}

# i have already defined separately inside ecs service capacity provider strategy so not needed here
resource "aws_ecs_cluster_capacity_providers" "cluster_attach" {
  for_each = local.ecs_apps

  cluster_name = aws_ecs_cluster.app_cluster.name
# Register BOTH providers at once
  capacity_providers = [
    aws_ecs_capacity_provider.ec2_provider["frontend"].name,
    aws_ecs_capacity_provider.ec2_provider["backend"].name
  ]
  
  # capacity_providers = [
  #   aws_ecs_capacity_provider.ec2_provider[each.key].name,
  # ]

  # default_capacity_provider_strategy {
  #   base              = 1
  #   weight            = 100
  #   capacity_provider = aws_ecs_capacity_provider.ec2_provider[each.key].name
  # }
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

#---------------------------------------------
# 10. ECS Task Definition
#---------------------------------------------


resource "aws_ecs_task_definition" "backend" {
  family                   = "lirw-ecr-backend"
  # network_mode             = "bridge"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  # Provisions a local Docker volume on the EC2 host's EBS drive
  volume {
    name = "backend_data_prod"
    docker_volume_configuration {
      scope         = "shared"
      autoprovision = true
      driver        = "local"
    }
  }
  volume {
    name = "backend_config_prod"
    docker_volume_configuration {
      scope         = "shared"
      autoprovision = true
      driver        = "local"
    }
  }

  container_definitions = jsonencode([
    {
      name      = "lirw_ecr_backend"
      image     = "node:16.0-alpine"
      # image     = var.mongo_image_uri
      essential = true
      
      # Resource limits moved to the container level to prevent host OOM issues
      memory    = var.app_cpu 
      cpu       = var.app_memory
      
      portMappings = [
        {
          containerPort = 3200
          # hostPort      = 27017
          protocol      = "tcp"
        }
      ]
      
      environment = [
        # { name = "DB_HOST", value = aws_db_instance.mysql_db.address },
        { name = "DB_DATABASE", value = aws_db_instance.mysql_db.db_name },
        { name = "DB_USER", value = aws_db_instance.mysql_db.username },
        { name = "DB_PORT", value = tostring(aws_db_instance.mysql_db.port) }
      ]

      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.rdsdb_root_password.arn },
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.rds_db_address.arn }
      ]

      mountPoints = [
        {
          sourceVolume  = "backend_data_prod"
          containerPath = "/data/db"
          readOnly      = false
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=3 --spider http://127.0.0.1:3200/health || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 5
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/lirwEcr-backend-${local.env_suffix}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group": "true",
        }
      }
    }
  ])
    lifecycle {
    ignore_changes = [
      container_definitions,
      # desired_count
    ]
  }

}

resource "aws_ecs_task_definition" "app" {
  family                   = "lirw-ecr-frontend"
  # network_mode             = "bridge"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "lirw_ecr_frontend"
      image     = var.app_image_uri
      essential = true
      memory    = var.app_memory
      cpu       = var.app_cpu
      
      portMappings = [
        {
          containerPort = 80
          # hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "BACKEND_ALB_URL", value = aws_lb.backend_internal.dns_name },
        { name = "VITE_API_URL", value = "/api" },
        
      ]

      healthCheck = {
        # curl command is missing in alpine linux
        # command     = ["CMD-SHELL", "curl -f http://localhost:3000 || exit 1"]
        # Using wget (native to Alpine), 127.0.0.1 (forces IPv4), and the new lightweight endpoint
        command     = ["CMD-SHELL", "wget --no-verbose --tries=3 --spider http://127.0.0.1:80/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 75
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/lirwEcr-frontend-${local.env_suffix}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group": "true"
        }
      }
    }
  ])
  lifecycle {
    ignore_changes = [
      container_definitions,
    ]
  }

}
#---------------------------------------------
# 11. ECS Service
#---------------------------------------------


# The Internal Network Load Balancer
resource "aws_lb" "backend_internal" {
  name               = "backend-internal-nlb-${local.env_suffix}"
  internal           = true
  load_balancer_type = "application"
  enable_cross_zone_load_balancing = true
  
  # Deploy this in your private subnets
  subnets            = [aws_subnet.pri_sub_3a.id, aws_subnet.pri_sub_4b.id]
  # subnets            = [aws_subnet.pub_sub_1a.id, aws_subnet.pub_sub_2b.id]

  # AWS recently added Security Group support for NLBs. 
  # This ensures only your App tier can talk to the database tier.
  security_groups    = [aws_security_group.internal_alb_sg.id]
}

# The TCP Listener
resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.backend_internal.arn
  # port              = "3200"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    # This references the target group we created in the previous step
    target_group_arn = aws_lb_target_group.backend_internal.arn
  }
}

# mongo db and internal alb terraform
# The Target Group for the Internal NLB (TCP Traffic)
resource "aws_lb_target_group" "backend_internal" {
  name     = "backend-internal-tg"
  port     = 3200
  protocol = "HTTP" # Crucial for MongoDB
  vpc_id   = aws_vpc.vpc.id
  # target_type = "ip" # Must be 'ip' when using awsvpc network mode
  target_type = "instance" # Must be 'instance' when using host/bridge network mode

  # ADD THIS LINE: Lower the wait time from 5 minutes to 30 seconds
  deregistration_delay = 30

  # Health check using TCP to ensure the port is open
  health_check {
    protocol            = "HTTP"
    path = "/health"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }
}

# The MongoDB ECS Service
resource "aws_ecs_service" "backend" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.app_cluster.id # Replace with your cluster ID
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.desired_count
  # launch_type     = "EC2"
  enable_execute_command = true

  # Attach the service to the NLB Target Group
  load_balancer {
    target_group_arn = aws_lb_target_group.backend_internal.arn
    container_name   = "lirw_ecr_backend"
    container_port   = 3200
  }


  timeouts {
    delete = "5m" 
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_provider["backend"].name
    weight            = 100
    base              = 1

  }

  health_check_grace_period_seconds = 60


  deployment_minimum_healthy_percent = 100 
  deployment_maximum_percent         = 200

  # lifecycle {
  #   ignore_changes = [
  #     # task_definition,
  #     # desired_count
  #   ]
  # }

  depends_on = [
    aws_lb_listener.backend_listener,
    # aws_ecs_cluster_capacity_providers.cluster_attach
  ]

  # Ensure the tasks are distributed across your EC2 instances (if running multiple)
  placement_constraints {
    type       = "distinctInstance"
  }
}

resource "aws_lb" "app_alb" {
  name               = "frontend-public-alb-${local.env_suffix}"
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
  name     = "lirw-frontend-tg"
  port     = 80
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
    path                = "/health" # Or a dedicated /api/health route
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
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.app_cluster.id # Replace with your cluster ID
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count # Assuming you want high availability
  # launch_type     = "EC2"
  enable_execute_command = true

  # Attach the service to the ALB Target Group
  load_balancer {
    target_group_arn = aws_lb_target_group.app_external.arn
    container_name   = "lirw_ecr_frontend"
    container_port   = 80
  }

  timeouts {
    delete = "5m" 
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2_provider["frontend"].name
    weight            = 100
    base              = 1

  }


  health_check_grace_period_seconds = 60

  
  deployment_minimum_healthy_percent = 100 
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [
      task_definition,
      # desired_count
    ]
  }

  depends_on = [
    aws_lb_listener.app_listener_https_secure,
    # aws_ecs_cluster_capacity_providers.cluster_attach
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


# Auto-scale tasks based on CPU Utilization

resource "aws_appautoscaling_target" "ecs_target" {
  for_each = {
    frontend = {
      min  = 2
      max  = 10
      name = aws_ecs_service.app.name      # Links to your frontend service
    }
    backend = {
      min  = 2
      max  = 10
      name = aws_ecs_service.backend.name  # Links to your backend service
    }
  }

  max_capacity       = each.value.max
  min_capacity       = each.value.min
  resource_id        = "service/${aws_ecs_cluster.app_cluster.name}/${each.value.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}


resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  for_each = aws_appautoscaling_target.ecs_target # Automatically loops through both

  name               = "${each.key}-cpu-autoscaling-${local.env_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = each.value.resource_id
  scalable_dimension = each.value.scalable_dimension
  service_namespace  = each.value.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 75.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}