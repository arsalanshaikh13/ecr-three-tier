#!/bin/bash
source .env_gitlab
# 1. Authenticate using the PAT (uses 'api' and 'read_user' scopes)
glab auth login --token "$GITLAB_TOKEN" --hostname gitlab.com
# Set SSH as the default protocol
glab config set git_protocol 

glab auth status
# Add local SSH key to GitLab profile
glab ssh-key add ~/.ssh/id_ed25519.pub --title "arsalanshaikh13-laptop"

# 2. Create the remote repo
glab repo create arsalanshaikh13/ecr-three-tier --public

# 3. Set CI/CD Variables (uses 'api' scope)
# These will be available in your .gitlab-ci.yml as environment variables



# Set AWS Region (Standard Variable)
glab variable set AWS_ACCOUNT_ID --value "750702272407" --repo arsalanshaikh13/ecr-three-tier
glab variable set ENV_VAR --value "dev"  --repo arsalanshaikh13/ecr-three-tier


# 4. Push code to trigger the pipeline (uses 'write_repository' scope)
git remote add gitlab $(glab repo view --json ssh_url_to_repo -q '.ssh_url_to_repo')
git add .
git commit -m "Initial CI/CD setup"
git push -u gitlab main

# 5. Monitor the pipeline immediately from the terminal
glab ci status
glab ci view
