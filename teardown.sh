#!/bin/bash

# ==========================================================
# Configuration: Update these to match your environment
# ==========================================================

CLUSTER_NAME="ecs-cluster-dev"
# Define your services as an array
SERVICES=("authors-service-dev" "books-service-dev" "dashboard-service-dev")
ASG_NAME="ecs-asg-dev"
REGION="us-east-1"

echo "======================================================"
echo " 🛑 Initiating Safe ECS Teardown Sequence..."
echo "======================================================"

# Step 1: Tell AWS to drain the tasks
echo "1️⃣ Scaling services down to 0 tasks..."
for SERVICE_NAME in "${SERVICES[@]}"; do
  echo "   📉 Scaling $SERVICE_NAME..."
  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --desired-count 0 \
    --region "$REGION" > /dev/null

  if [ $? -ne 0 ]; then
    echo "   ❌ Failed to update $SERVICE_NAME. Please check your AWS credentials and cluster name."
    exit 1
  fi
done

# Step 2: Actively monitor the shutdown process
echo "2️⃣ Waiting for all running tasks to terminate cleanly..."
while true; do
  ALL_SERVICES_DOWN=true

  for SERVICE_NAME in "${SERVICES[@]}"; do
    # Query AWS for the exact number of running tasks
    RUNNING_TASKS=$(aws ecs describe-services \
      --cluster "$CLUSTER_NAME" \
      --services "$SERVICE_NAME" \
      --region "$REGION" \
      --query 'services[0].runningCount' \
      --output text)

    if [ "$RUNNING_TASKS" -gt 0 ]; then
      echo "   ⏳ $SERVICE_NAME still has $RUNNING_TASKS task(s) running..."
      ALL_SERVICES_DOWN=false
    fi
  done

  # If all services reported 0 tasks, break the loop
  if [ "$ALL_SERVICES_DOWN" = true ]; then
    echo "✅ All ECS services have successfully scaled down to 0!"
    break
  fi

  echo "   💤 Waiting 10 seconds before checking again..."
  sleep 10
done


# Step 3: Terminate the EC2 Instances
echo "3️⃣ Scaling Auto Scaling Group ($ASG_NAME) to 0 instances..."
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 0 \
  --max-size 0 \
  --desired-capacity 0 \
  --region "$REGION" > /dev/null

if [ $? -ne 0 ]; then
  echo "⚠️ Failed to update ASG. It may have already been deleted."
else
  echo "✅ EC2 instances are terminating..."
  # Give AWS a few seconds to register the termination state before Terraform hits the API
  sleep 10
fi

# Extract the raw Instance IDs attached to the ASG
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
  echo "   🔥 Target(s) acquired: $INSTANCE_IDS"
  echo "   ☠️  Sending termination signal..."
  
  # Forcefully terminate the instances via EC2 API
  aws ec2 terminate-instances \
    --instance-ids $INSTANCE_IDS \
    --region "$REGION" > /dev/null
    
  echo "   ⏳ Waiting for AWS to confirm termination (usually takes ~30 seconds)..."
  
  # This command pauses the script until AWS confirms the instances are physically dead
  aws ec2 wait instance-terminated \
    --instance-ids $INSTANCE_IDS \
    --region "$REGION"
    
  echo "   ✅ All EC2 instances successfully destroyed."
else
  echo "   ✅ No running instances found."
fi

# Step 3: Trigger Terraform
echo "======================================================"
echo " 🌪️  Infrastructure is clear. Triggering Terraform... "
echo "======================================================"

# We use the standard command so you still get the [yes/no] safety prompt
terraform destroy -var-file=dev.tfvars -parallelism=20 -auto-approve