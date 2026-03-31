#!/bin/bash

# # Ensure config directory exists
# mkdir -p ~/.config/glab-cli

# # Set default protocols and disable the telemetry that caused your 401 error
# glab config set api_protocol https --global
# glab config set git_protocol ssh --global
# glab config set check_update false --global

# Disable the usage reporting to stop the 401 Unauthorized noise
# export GLAB_REPORT_USAGE=false

source ./gh_glab_scripts/.env_gitlab
echo "gitlab token : $GITLAB_TOKEN "
# To explicitly disable the usage tracking causing the error:
export GLAB_REPORT_USAGE=false

# 1. Authenticate using the PAT (uses 'api' and 'read_user' scopes)
glab auth login --token "$GITLAB_TOKEN" --hostname gitlab.com
# Set SSH as the default protocol
# glab config set git_protocol  ssh --global
# glab config set api_protocol https --global

glab auth status
# Add local SSH key to GitLab profile
glab ssh-key add ~/.ssh/id_ed25519.pub --title "arsalanshaikh13-laptop"

# 2. Create the remote repo
glab repo create arsalanshaikh13/ecr-three-tier --public

# 3. Set CI/CD Variables (uses 'api' scope)
# These will be available in your .gitlab-ci.yml as environment variables

# GitLab allows certain roles to override variables when running a pipeline manually.
#  You can set this to owner, maintainer, developer, 
# or no_one_allowed (represented by null or specific strings in the API).
glab api --method PUT projects/arsalanshaikh13%2Fecr-three-tier \
  -f ci_pipeline_variables_minimum_override_role="maintainer"

# If you want to ensure that only the roles defined above can use variables in the pipeline,
#  you may want to toggle the restriction setting:
# Enable the restriction so only the minimum role can use pipeline variables
glab api --method PUT projects/arsalanshaikh13%2Fecr-three-tier \
  -f restrict_user_defined_variables=true

# Set AWS Region (Standard Variable)
glab variable set AWS_ACCOUNT_ID --value "750702272407" --repo arsalanshaikh13/ecr-three-tier
glab variable set ENV_VAR --value "dev"  --repo arsalanshaikh13/ecr-three-tier


# 4. Push code to trigger the pipeline (uses 'write_repository' scope)
git remote add gitlab $(glab repo view arsalanshaikh13/ecr-three-tier -F json | jq -r '.ssh_url_to_repo')
git add .
git commit -m "Initial gitlab CI/CD setup for ecr-three-tier for host network"
git push -u gitlab gitlab-public

# 5. Monitor the pipeline immediately from the terminal
glab ci status
glab ci view