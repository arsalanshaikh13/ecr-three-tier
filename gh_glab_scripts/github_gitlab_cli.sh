#!/bin/bash


# --- 1. SSH KEY GENERATION ---
echo "🔑 Generating SSH Key..."
SSH_PATH="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_PATH" ]; then
    ssh-keygen -t ed25519 -C "m.arsalanshaikh13@gmail.com" -f "$SSH_PATH" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$SSH_PATH"
else
    echo "✅ SSH Key already exists at $SSH_PATH"
fi

# --- Get PAT Tokens of github and gitlab ---
# we have to get PAT tokens for UI for the first time with (repo, 'admin:public_key', 'admin:ssh_signing_key', 'gist') scope
# ideally store them in .env file
# GitHub Token (Repo, Workflow, Write:Packages scopes)
export GH_TOKEN="ghp_XXXXXXXXXXXXXXXXXXXX"

# GitLab Token (API, Read/Write Repository scopes)
export GITLAB_TOKEN="glpat-XXXXXXXXXXXXXXXX"

# Your User Details
export GH_USER="arsalanshaikh13"
export GL_USER="arsalanshaikh13"


# # Load tokens from .env
# if [ -f .env ]; then
#     source .env
#     echo "✅ Tokens loaded from .env"
# else
#     echo "❌ .env file not found!"
#     exit 1
# fi

# --- 2. NON-INTERACTIVE LOGIN ---
echo "🔓 Authenticating CLIs..."
# GitHub
echo "$GH_TOKEN" | gh auth login --with-token

gh config set git_protocol ssh -h github.com
gh auth status

# --- 3. RE-AUTHENTICATE SCOPES (GitHub) ---
echo "🔄 Refreshing GitHub Scopes for SSH Management..."
gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key

# --- 4. ADD SSH KEYS TO ACCOUNTS ---
echo "📤 Uploading SSH Keys..."
gh ssh-key add "${SSH_PATH}.pub" --title "Automation-Key-$(date +%F)"

# --- 5. VERIFY SSH CONNECTION ---
echo "Verify GitHub SSH..."
ssh -T git@github.com -o StrictHostKeyChecking=no || true

# --- 6. REPO-LEVEL VARIABLES & SECRETS (GitHub) ---
REPO="arsalanshaikh13/ecr-three-tier"
echo "⚙️ Setting Repo Variables & Secrets..."
gh variable set AWS_REGION --body "us-east-1" --repo "$REPO"
gh secret set AWS_SECRET_KEY --body "super-secret-value" --repo "$REPO"

# Clean up/Delete example
gh variable delete AWS_REGION --repo "$REPO"

# --- 7. ENVIRONMENT & PROTECTION RULES (GitHub) ---
echo "🛡️ Creating Environment with Protection Rules..."
USER_ID_1=$(gh api user --jq '.id')

# Create Environment 'production' with Reviewers and No Self-Review
# echo "{
#   \"wait_timer\": 0,
#   \"prevent_self_review\": true,
#   \"reviewers\": [{\"type\": \"User\", \"id\": $USER_ID_1}],
#   \"deployment_branch_policy\": {
#     \"protected_branches\": false,
#     \"custom_branch_policies\": true
#   }
# }" | gh api --method PUT "repos/$REPO/environments/production" --input -


# Create/Update Environment with JSON rules (Reviewers, No Self-Review)
echo '{
  "wait_timer": 0,
  "prevent_self_review": true,
  "reviewers": [{"type": "User", "id": $USER_ID_1}],
  "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}
}' | gh api --method PUT repos/owner/repo/environments/production --input -

# Add Branch & Tag Policies (Only allow main and version tags)
gh api --method POST repos/owner/repo/environments/production/deployment-branch-policies -f name='main' -f type='branch'
gh api --method POST repos/owner/repo/environments/production/deployment-branch-policies -f name='v*' -f type='tag'

# Delete the entire environment
gh api --method DELETE repos/owner/repo/environments/production

# --- 8. DEPLOYMENT BRANCH & TAG POLICIES ---
echo "📜 Setting Branch/Tag Policies..."
# Allow 'main' branch
gh api --method POST "repos/$REPO/environments/production/deployment-branch-policies" -f name='main' -f type='branch'
# Allow version tags (v1.0, etc)
gh api --method POST "repos/$REPO/environments/production/deployment-branch-policies" -f name='v*' -f type='tag'



# 4. Initialize Local Git
git init
git add .
git commit -m "Initial commit from bootstrapper"
git branch -M main
git remote add origin "git@github.com:$GH_USER/$REPO_NAME.git"

echo "✅ Ready to push! Just run 'git push -u origin main'"


# GitLab
# --- 2. NON-INTERACTIVE LOGIN ---
# Non-interactive login (requires GITLAB_TOKEN env var)
glab auth login --token "$GL_TOKEN" --hostname gitlab.com
# Set SSH as the default protocol
glab config set git_protocol 

glab auth status
# Add local SSH key to GitLab profile
glab ssh-key add ~/.ssh/id_ed25519.pub --title "My-Laptop"

# --- 4. ADD SSH KEYS TO ACCOUNTS ---
# add ssh keys
glab ssh-key add "${SSH_PATH}.pub" --title "Automation-Key-$(date +%F)"

# --- 5. VERIFY SSH CONNECTION ---
echo "Verify GitLab SSH..."
ssh -T git@gitlab.com -o StrictHostKeyChecking=no || true


# --- 6. REPO-LEVEL VARIABLES & SECRETS (GitHub) ---
echo "🦊 Setting GitLab Variables..."
# Set a variable for a specific environment (scope)
glab variable set AWS_REGION --value "us-east-1" --scope "production" --repo owner/repo
# Set a Secret (Masked = hidden in logs, Protected = only on protected branches)
glab variable set DB_PASSWORD --value "password123" --masked --protected --scope "production"
# Delete a variable
glab variable delete AWS_REGION --scope "production" --repo owner/repo

# --- 7. ENVIRONMENT & PROTECTION RULES (GitHub) ---
# Add Branch & Tag Policies (Only allow main and version tags)
# Create an environment
glab api --method POST projects/owner%2Frepo/environments -f name="production"

# Protect the environment (Require Maintainer access level 40)
glab api --method POST projects/owner%2Frepo/protected_environments \
  -f name="production" \
  -f deploy_access_levels='[{"access_level": 40}]'

# Delete an environment
glab api --method DELETE projects/owner%2Frepo/environments/production


# 4. Initialize Local Git for gitlab
git init
git add .
git commit -m "Initial commit from bootstrapper"
git branch -M main
git remote add origin "git@gitlab.com:$GH_USER/$REPO_NAME.git"

echo "✅ Ready to push! Just run 'git push -u origin main'"



echo "🎯 Script completed successfully!"