#!/bin/bash

# Git Commit & Sync Script - /git-sync.sh
# Syncs local repository with remote and optionally triggers Cloud CI/CD

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Commit Message 
commit_message="Auto Update : Fixes"

echo -e "${BLUE}Starting MuziiNap Music git sync...${NC}"

# Stage all changes
echo -e "${BLUE}Staging changes...${NC}"
git add .

# Commit changes
echo -e "${BLUE}Committing changes...${NC}"
read -p "Enter commit message [Auto Update : Fixes]: " input_msg
commit_message=${input_msg:-"Auto Update : Fixes"}
git commit -m "$commit_message" || echo "No changes to commit"

# Fetch latest changes from remote (this also fetches the latest tags)
echo -e "${BLUE}Fetching from remote...${NC}"
git fetch origin

# Pull latest changes to current branch
echo -e "${BLUE}Pulling changes...${NC}"
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

# Push local commits to remote
echo -e "${BLUE}Pushing changes...${NC}"
git push origin "$(git rev-parse --abbrev-ref HEAD)"

echo -e "${GREEN}Git sync completed successfully!${NC}"
echo ""

# ==========================================
# 🚀 CLOUD PIPELINE TRIGGER
# ==========================================
echo -e "${YELLOW}--- Release Manager ---${NC}"
read -p "Do you want to trigger a Cloud Release for these changes? (y/n): " trigger_release

if [[ "$trigger_release" == "y" || "$trigger_release" == "Y" ]]; then
    echo -e "${RED}WAIT! Have you updated pubspec.yaml, CHANGELOG.md, and the in-app version string?${NC}"
    read -p "Proceed with release? (y/n): " confirm_docs
    if [[ "$confirm_docs" != "y" && "$confirm_docs" != "Y" ]]; then
        echo -e "${BLUE}Release aborted. Please update the version information and changelog, then try again!${NC}"
        exit 0
    fi
    
    read -p "Enter version tag (e.g., v1.0.0 or v0.0.0 for testing): " version_tag
    
    echo -e "${BLUE}Preparing tag $version_tag...${NC}"
    
    # Check if the tag already exists (we fetched earlier, so local knowledge is up-to-date)
    if git rev-parse -q --verify "refs/tags/$version_tag" >/dev/null; then
        echo -e "${RED}Warning: Tag '$version_tag' already exists!${NC}"
        read -p "Can I remove it and replace it with the current code? (y/n): " replace_tag
        
        if [[ "$replace_tag" == "y" || "$replace_tag" == "Y" ]]; then
            echo -e "${YELLOW}Deleting old tag '$version_tag'...${NC}"
            git tag -d "$version_tag" 2>/dev/null || true
            git push origin --delete "$version_tag" 2>/dev/null || true
        else
            echo -e "${BLUE}Release aborted to protect the existing tag. Have a great day!${NC}"
            exit 0
        fi
    fi
    
    # Create the brand new tag on the current code
    echo -e "${BLUE}Tagging current code as $version_tag...${NC}"
    git tag "$version_tag"
    
    # Push the new tag to GitHub to wake up the CI/CD servers
    git push origin "$version_tag"
    
    echo -e "${GREEN}Boom! Release tag pushed.${NC}"
    echo -e "${GREEN}The GitHub Cloud Servers are now compiling your apps!${NC}"
else
    echo -e "${BLUE}Skipping release. Have a great day!${NC}"
fi

# ==========================================
