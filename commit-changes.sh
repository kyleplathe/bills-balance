#!/bin/bash
# Quick commit script for BillsAndBalance
# Usage: ./commit-changes.sh "Your commit message"

PROJECT_DIR="/Volumes/Extreme Pro/Work/Dev Project/Bill&Balance"
cd "$PROJECT_DIR" || exit 1

if [ -z "$1" ]; then
    echo "Usage: $0 \"Your commit message\""
    exit 1
fi

COMMIT_MSG="$1"

# Check if there are changes
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit."
    exit 0
fi

# Add all changes
git add .

# Commit with message
git commit -m "$COMMIT_MSG"

# Push to remote
echo "Pushing to remote..."
git push

echo "✅ Changes committed and pushed!"
