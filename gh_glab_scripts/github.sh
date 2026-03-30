# gh auth login

# # Set the AWS Account ID
# gh variable set ACCOUNT_ID --body "750702272407" --repo arsalanshaikh13/ecr-three-tier

# # Set the AWS Region
# gh variable set AWS_REGION --body "us-east-1" --repo arsalanshaikh13/ecr-three-tier

# # Set the Environment Variable
# gh variable set ENV_VAR --body "dev" --repo arsalanshaikh13/ecr-three-tier
# gh variable delete ENV_VAR  --repo arsalanshaikh13/ecr-three-tier
# gh secret delete ENV_VAR  --repo arsalanshaikh13/ecr-three-tier 


# set variable and secret for environment
# gh variable set ENV_VAR --body "dev" --repo arsalanshaikh13/ecr-three-tier --env test
# gh secret set ENV_VAR --body "dev" --repo arsalanshaikh13/ecr-three-tier --env test
# gh secret delete ENV_VAR  --repo arsalanshaikh13/ecr-three-tier --env test


# 1. Create the environment
# gh api --method PUT repos/arsalanshaikh13/ecr-three-tier/environments/production

# # get user id in integer value
# user_id=$(gh api users/arsalanshaikh13 --jq '.id')

# # # Replace <YOUR_USER_ID> with your actual GitHub ID (e.g., 1234567)
# # gh api --method PUT repos/arsalanshaikh13/ecr-three-tier/environments/test \
# #   -f wait_timer=0 \
# #   -F prevent_self_review=true \
# #   -F reviewers='[{"type":"User","id":$user_id},{"type":"User","id":$user_id}]' \
# #   -F deployment_branch_policy='{"protected_branches":false,"custom_branch_policies":true}' \

# # 1. Get your IDs (ensure these variables are populated)
# USER_ID_1=$(gh api user --jq '.id')
# USER_ID_2=$(gh api users/arsalanshaikh12 --jq '.id')

# # 2. Create/Update Environment with Protection Rules
# # Using --input - allows us to pass a clean JSON block
# echo "{
#   \"wait_timer\": 10,
#   \"prevent_self_review\": true,
#   \"reviewers\": [
#     {\"type\": \"User\", \"id\": $USER_ID_1},
#     {\"type\": \"User\", \"id\": $USER_ID_2}
#   ],
#   \"deployment_branch_policy\": {
#     \"protected_branches\": false,
#     \"custom_branch_policies\": true
#   }
# }" | gh api --method PUT repos/arsalanshaikh13/ecr-three-tier/environments/test --input -

# # 3. Add the Branch Policy (Run ONLY after the command above succeeds)
# # 2. Then, define which branch is allowed (e.g., 'main')
# gh api --method POST repos/arsalanshaikh13/ecr-three-tier/environments/test/deployment-branch-policies \
#   -f name='main' \
#   -f type='branch'

# # 2. Now run your variable command again
# gh variable set AWS_REGION --body "us-east-1" --repo arsalanshaikh13/ecr-three-tier --env test

# # Allow the 'main' branch
# gh api --method POST repos/arsalanshaikh13/ecr-three-tier/environments/test/deployment-branch-policies \
#   -f name='main' -f type='branch'

# # Allow any branch starting with 'feature/'
# gh api --method POST repos/arsalanshaikh13/ecr-three-tier/environments/test/deployment-branch-policies \
#   -f name='feature/*' -f type='branch'

#   # Allow any tag starting with 'v' (e.g., v1.0.0)
# gh api --method POST repos/arsalanshaikh13/ecr-three-tier/environments/test/deployment-branch-policies \
#   -f name='v*' -f type='tag'

# # Allow specific release tags
# gh api --method POST repos/arsalanshaikh13/ecr-three-tier/environments/test/deployment-branch-policies \
#   -f name='release-*' -f type='tag'

# # # delete the environment
# gh api --method DELETE repos/arsalanshaikh13/ecr-three-tier/environments/test
# gh api --method DELETE repos/arsalanshaikh13/ecr-three-tier/environments/production
# gh api --method DELETE repos/arsalanshaikh13/ecr-three-tier/environments/dev




# setup the ssh login for gh
# Generate a new Ed25519 SSH key (recommended)
ssh-keygen -t ed25519 -C "m.arsalanshaikh13@gmail.com"

# Start the ssh-agent in the background
eval "$(ssh-agent -s)"

# Add your private key to the agent
ssh-add ~/.ssh/id_ed25519

# Verify the Connection
ssh -T git@github.com

# Starts the interactive login. Choose SSH as the preferred protocol.
gh auth login
# Or
# non interactive login
echo "<your_gh_token>" | gh auth login --with-token --hostname github.com
# read token from file to avoid putting the token in your process tree:
gh auth login --with-token < mytoken.txt


# Re-authenticates with specific "scopes" (permissions) to manage keys.
gh auth refresh -h github.com -s admin:public_key 
# Uploads your local public key to your GitHub account.
gh ssh-key add ~/.ssh/id_ed25519.pub --title "Laptop"

# Verify the Connection
ssh -T git@github.com