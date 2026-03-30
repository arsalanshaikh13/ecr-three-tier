#!/bin/bash
# Usage: ./bootstrap.sh my-new-app
REPO_NAME=$1
source .env

echo "🚀 Bootstrapping $REPO_NAME..."

# 1. Create GH Repo
gh repo create "$GH_USER/$REPO_NAME" --private

# 2. Set AWS Environment Variables (Repo Level)
gh variable set AWS_REGION --body "us-east-1" --repo "$GH_USER/$REPO_NAME"
gh variable set ACCOUNT_ID --body "750702272407" --repo "$GH_USER/$REPO_NAME"

# 3. Create 'production' Environment & Secrets
echo "Creating production env..."
gh api --method PUT "repos/$GH_USER/$REPO_NAME/environments/production"

gh secret set AWS_ACCESS_KEY --body "AKIA..." --repo "$GH_USER/$REPO_NAME" --env production

# 4. Initialize Local Git
git init
git add .
git commit -m "Initial commit from bootstrapper"
git branch -M main
git remote add origin "git@github.com:$GH_USER/$REPO_NAME.git"

echo "✅ Ready to push! Just run 'git push -u origin main'"