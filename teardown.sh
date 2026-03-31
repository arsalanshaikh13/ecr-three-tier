#!/bin/bash

# ==========================================================
# Configuration: Update these to match your environment
# ==========================================================
CLUSTER_NAME="ecs-cluster-dev"
REGION="us-east-1"

# Define the arrays for your multiple services and target groups
TARGET_GROUPS=("backend-internal-tg" "lirw-frontend-tg" )
SERVICES=("backend-service" "frontend-service")

echo "======================================================"
echo " 🛑 Initiating Safe ECS Teardown Sequence..."
echo "======================================================"

# Step 1: Remove the Load Balancer's safety net
echo "1️⃣ Modifying Target Groups to drop connections instantly..."

for TG_NAME in "${TARGET_GROUPS[@]}"; do
  echo "   🔄 Checking Target Group: $TG_NAME..."
  
  # Retrieve the exact ARN of the Target Group
  TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

  if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
    # Force the draining delay to 0 seconds
    aws elbv2 modify-target-group-attributes \
      --target-group-arn "$TG_ARN" \
      --attributes Key=deregistration_delay.timeout_seconds,Value=0 \
      --region "$REGION" > /dev/null
    echo "      ✅ Deregistration delay set to 0. Safety nets removed."
  else
    echo "      ⚠️ Target Group not found (It may already be deleted). Proceeding..."
  fi
done

# Step 2: Tell AWS to drain the tasks
echo ""
echo "2️⃣ Scaling all services down to 0 tasks..."

for SERVICE_NAME in "${SERVICES[@]}"; do
  echo "   📉 Scaling $SERVICE_NAME..."
  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --desired-count 0 \
    --region "$REGION" > /dev/null 2>&1
    
  if [ $? -ne 0 ]; then
    echo "      ⚠️ Failed to update $SERVICE_NAME. (It may not exist). Proceeding..."
  fi
done

# Step 3: Actively monitor the shutdown process
echo ""
echo "3️⃣ Waiting for all running tasks to terminate cleanly..."

while true; do
  ALL_SERVICES_DOWN=true

  for SERVICE_NAME in "${SERVICES[@]}"; do
    # Query AWS for the exact number of running tasks
    RUNNING_TASKS=$(aws ecs describe-services \
      --cluster "$CLUSTER_NAME" \
      --services "$SERVICE_NAME" \
      --region "$REGION" \
      --query 'services[0].runningCount' \
      --output text 2>/dev/null)

    # Check if the query returned a valid number (handles "service not found" edge cases)
    if [[ ! "$RUNNING_TASKS" =~ ^[0-9]+$ ]]; then
      RUNNING_TASKS=0 # Treat missing services as having 0 tasks
    fi

    if [ "$RUNNING_TASKS" -gt 0 ]; then
      echo "   ⏳ $SERVICE_NAME still has $RUNNING_TASKS task(s) running..."
      ALL_SERVICES_DOWN=false
    fi
  done

  # If all services reported 0 tasks, break the loop
  if [ "$ALL_SERVICES_DOWN" = true ]; then
    echo "   ✅ All tasks across all services have been successfully terminated."
    break
  fi

  echo "   💤 Waiting 10 seconds before checking again..."
  sleep 10
done

# Step 4: Force delete the services
echo ""
echo "4️⃣ Force deleting ECS services..."

for SERVICE_NAME in "${SERVICES[@]}"; do
  echo "   🗑️ Deleting $SERVICE_NAME..."
  aws ecs delete-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --region "$REGION" \
    --force \
    --no-cli-pager > /dev/null 2>&1
    
  # Note: A second non-force delete is usually redundant if --force is used, 
  # but left out here to keep the terminal output clean and prevent duplicate errors.
done

# Step 5: Trigger Terraform
echo ""
echo "======================================================"
echo " 🌪️  Infrastructure is clear. Triggering Terraform... "
echo "======================================================"

# Run Terraform Destroy
terraform destroy -var-file=dev.tfvars -parallelism=20 -auto-approve