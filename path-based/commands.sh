# docker compose --env-file=.env.example build
# aws ecr describe-repositories

# aws ecr create-repository \
#     --repository-name dashboard-repo \
#     --region us-east-1
# aws ecr create-repository \
#     --repository-name books-repo \
#     --region us-east-1
# aws ecr create-repository \
#     --repository-name authors-repo \
#     --region us-east-1

# aws ecr describe-repositories

# aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 513410254332.dkr.ecr.us-east-1.amazonaws.com

# docker tag dashboard:latest 513410254332.dkr.ecr.us-east-1.amazonaws.com/dashboard-repo:latest
# docker tag books:latest 513410254332.dkr.ecr.us-east-1.amazonaws.com/books-repo:latest
# docker tag authors:latest 513410254332.dkr.ecr.us-east-1.amazonaws.com/authors-repo:latest

# docker push 513410254332.dkr.ecr.us-east-1.amazonaws.com/dashboard-repo:latest
# docker push 513410254332.dkr.ecr.us-east-1.amazonaws.com/books-repo:latest
# docker push 513410254332.dkr.ecr.us-east-1.amazonaws.com/authors-repo:latest

# aws ecr list-images --repository-name authors-repo --region us-east-1
# aws ecr list-images --repository-name books-repo --region us-east-1
# aws ecr list-images --repository-name dashboard-repo --region us-east-1


# You are an Amazon ECS troubleshooting expert. 
# Actively investigate service deployment issue by making read-only API calls and analyzing results to determine the root cause. 
# WORKFLOW: 1) Investigate by executing all troubleshooting steps 2) Analyze data OUTPUT: 1) Root Cause 2)Resolution recommendations
#  Base your analysis only on verifiable data from AWS APIs. If data is insufficient to reach a conclusion,
#  explicitly state what additional data is needed. Deployment: Cluster ARN: arn:aws:ecs:us-east-1:513410254332:cluster/ec2-micro 
# Service ARN: arn:aws:ecs:us-east-1:513410254332:service/ec2-micro/task-definition-dashboard-ec2e1-service-kt2giifb 
# Status: ROLLBACK_FAILED Status Reason: No rollback candidate was found to run the rollback. 
# Task Definition ARN: arn:aws:ecs:us-east-1:513410254332:task-definition/task-definition-dashboard-ec2e1:1
#  Timeline: Created: 2026-02-26T09:05:49.208Z Updated: 2026-02-26T09:07:11.532Z Started: 2026-02-26T09:05:49.283Z

aws ecs list-task-definitions --status ACTIVE \
  --query 'taskDefinitionArns[]' --output text  --no-cli-pager | \
tr '\t' '\n' | \
./task-def.sh