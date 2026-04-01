#!/bin/bash
# Ensure your token is exported first
source ./gh_glab_scripts/.env_circleci

# setup non interactively circleci cli
# circleci setup --no-prompt --token $CIRCLECI_TOKEN --host https://circleci.com


# --- CONFIGURATION ---
VCS="gh" # 'gh' for GitHub, 'bb' for Bitbucket
ORG="arsalanshaikh13"
REPO="ecr-three-tier"
# REPO="ecr-oidc-nextjs"
CONTEXT_NAME="aws-ecr-context"
# Ensure export CIRCLECI_TOKEN="your_personal_token" is in your environment

echo "🚀 Bootstrapping CircleCI for $ORG/$REPO..."

# 1. Get Organization ID
# We use the 'collaborations' endpoint to find the Org UUID
ORG_ID=$(curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
               https://circleci.com/api/v2/me/collaborations | jq -r '.[0].id')

# if [[ -z "$ORG_ID" || "$ORG_ID" == "null" ]]; then
#     echo "❌ Failed to get Org ID. Check your token."
#     exit 1
# fi
echo "✅ Org ID: $ORG_ID"

# 2. Follow (Create) Project in CircleCI
# This 'activates' the repo in CircleCI so it starts listening for pushes
echo "🔗 Following project..."
# Using 'gh' slug as returned by your previous API call

# Enable/Follow the repo
# 1. Get GitHub Repository ID (Numeric)
# CircleCI needs this to identify the 'external_id'
# GITHUB_REPO_ID=$(gh api repos/$ORG/$REPO --jq '.id')

# 3. Get Project ID
# PROJECT_ID=$(curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
#                    "https://circleci.com/api/v2/project/$VCS/$ORG/$REPO" | jq -r '.id')
echo "✅ Project ID: $PROJECT_ID"

# Variables for clarity
REPO_NAME="ecr-three-tier"

# Get project details
# curl --request GET \
#   --url https://circleci.com/api/v2/project/gh/$ORG/$REPO \
#   --header "Circle-Token: $CIRCLE_TOKEN"

# create project
# curl -s --request POST \
#   --url "https://circleci.com/api/v2/organization/$ORG_ID/project" \
#   --header "Circle-Token: $CIRCLECI_TOKEN" \
#   --header "Content-Type: application/json" \
#   --data "{\"name\": \"$REPO_NAME\"}"



# # --- 1. Get GitHub Repository ID (External ID) ---
# # CircleCI needs the numeric ID from GitHub for the 'external_id' field
# GITHUB_REPO_ID=$(gh api repos/arsalanshaikh13/ecr-three-tier --jq '.id')


# # https://circleci.com/docs/api/v2/#tag/Pipeline-Definition/operation/getPipelineDefinition
# Get pipeline definition id
# GET_RESPONSE=$(curl --request GET \
#   --url https://circleci.com/api/v2/projects/$PROJECT_ID/pipeline-definitions \
#   --header "Circle-Token: $CIRCLECI_TOKEN" )

# Extract the new Pipeline Definition ID for future updates
# PIPELINE_DEF_ID=$(echo $GET_RESPONSE | jq -r '.items[0].id')
echo "✅ Created Pipeline Definition: $PIPELINE_DEF_ID"


# create pipeline
# curl -s -X POST "https://circleci.com/api/v2/project/$VCS/$ORG/$REPO/pipeline" \
#      -H "Circle-Token: $CIRCLECI_TOKEN" \
#      -H "Content-Type: application/json" \
#      -d '{"branch":"circleci-public"}'

# recommended api call for creating pipeline
# curl --request POST \
#   --url https://circleci.com/api/v2/project/$VCS/$ORG/$REPO/pipeline/run \
#   --header "Circle-Token: $CIRCLECI_TOKEN" \
#   --header "Content-Type: application/json" \
#   --data "{
#   \"definition_id\": \"$PIPELINE_DEF_ID\",
#   \"config\": {
#     \"branch\": \"circleci-public\"
#   },
#   \"checkout\": {
#     \"branch\": \"circleci-public\"
#   },
#   \"parameters\": {
#             \"manual_trigger\": true,
#             \"build_frontend\": true,
#             \"get_frontend\": false,
#             \"build_backend\": true,
#             \"get_backend\": false,
#             \"run_seeding\": true
#           }

# }"

curl --request POST \
  --url "https://circleci.com/api/v2/project/$VCS/$ORG/$REPO/pipeline" \
  --header "Circle-Token: $CIRCLECI_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
    "branch": "circleci-public",
    "parameters": {
      "manual_trigger": true,
      "build_frontend": false,
      "get_frontend": true,
      "build_backend": false,
      "get_backend": true,
      "run_seeding": true
    }
  }'

# echo "$PIPELINE pipeline"
# PIPELINE_ID=$(echo "$PIPELINE" | jq -r '.id')
# # see pipeline progress
# curl -H "Circle-Token: $CIRCLECI_TOKEN" \
#      "https://circleci.com/api/v2/pipeline/$PIPELINE_ID/config"

# # You must use the same type of reference (either 'branch' or 'tag') for both 'checkout' and 'config'

# # # 4. Create Organization Context (Global Secrets)
# # # We use the native CLI for contexts as it handles the logic better than raw curl
# # echo "🛡️ Creating Context: $CONTEXT_NAME..."
# # circleci context create $VCS $ORG $CONTEXT_NAME || echo "⚠️ Context already exists."

# # # 5. Add Variables to Context (Non-Interactive)
# # # Piping the value avoids the interactive prompt
# # printf "us-east-1" | circleci context store-secret $VCS $ORG $CONTEXT_NAME AWS_REGION
# printf "750702272407" | circleci context store-secret $VCS $ORG $CONTEXT_NAME ACCOUNT_ID
# echo "750702272407" | circleci context store-secret $VCS $ORG $CONTEXT_NAME ACCOUNT_ID
# echo "🎉 CircleCI infrastructure is ready for $REPO!"

# # Create the context
# circleci context create gh arsalanshaikh13 aws-ecr-

# show environment variable from context

VCS="gh" # 'gh' for GitHub, 'bb' for Bitbucket
ORG="arsalanshaikh13"

# circleci context show gh arsalanshaikh13  aws-ecr-context

# create context through api call
# curl --request POST \
#   --url https://circleci.com/api/v2/context \
#   --header "Circle-Token: $CIRCLECI_TOKEN" \
#   --header "Content-Type: application/json" \
#   --data "{
#   \"name\": \"example-string\",
#   \"owner\": { \"id\": \"$ORG_ID\"}
# }"

# Add a variable only for this project
# curl -s -X POST "https://circleci.com/api/v2/project/$VCS/$ORG/$REPO/envvar" \
#      -H "Circle-Token: $CIRCLECI_TOKEN" \
#      -H "Content-Type: application/json" \
#      -d '{"name":"ENV_VAR","value":"dev"}'

# Delete environment variable
# variabl="dev"
# curl -s -X DELETE "https://circleci.com/api/v2/project/$VCS/$ORG/$REPO/envvar/$variabl" \
#      -H "Circle-Token: $CIRCLECI_TOKEN" \
#      -H "Content-Type: application/json" \

# # # Add variables to the context (Masked/Encrypted)
# printf "us-east-1" | circleci context store-secret gh arsalanshaikh13 example-string AWS_REGION
# printf "750702272407" | circleci context store-secret gh arsalanshaikh13 aws-ecr-context ACCOUNT_ID
# printf "dev" | circleci context store-secret gh arsalanshaikh13 aws-ecr-context ENV_VAR

# delete variable
# circleci context remove-secret gh arsalanshaikh13 aws-ecr-context AWS_REGION



# get context
# CONTEXT_ID=$(curl --request GET \
#   --url "https://circleci.com/api/v2/context?owner-id=$ORG_ID&owner-type=organization" \
#   --header "Circle-Token: $CIRCLECI_TOKEN" | jq -r '.items[3].id')
# echo "$CONTEXT_ID context id"

# curl --request GET \
#   --url "https://circleci.com/api/v2/context/$CONTEXT_ID/environment-variable" \
#   --header "Circle-Token: $CIRCLECI_TOKEN"
# Delete the context through API
# curl --request DELETE \
#   --url https://circleci.com/api/v2/context/$CONTEXT_ID \
#   --header "Circle-Token: $CIRCLECI_TOKEN"



# documentation for circleci cli
# https://circleci-public.github.io/circleci-cli/circleci_context.html


# document for circleci api calls
# # https://circleci.com/docs/api/v2/#tag/Pipeline-Definition/operation/getPipelineDefinition
