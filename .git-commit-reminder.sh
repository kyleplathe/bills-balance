#!/bin/bash
# Git Commit Reminder Script
# Run this script regularly (e.g., via cron or manually) to remind you to commit changes

PROJECT_DIR="/Volumes/Extreme Pro/Work/Dev Project/Bill&Balance"
cd "$PROJECT_DIR" || exit 1

# Check if there are uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    MODIFIED_COUNT=$(git status --porcelain | wc -l | tr -d ' ')
    MODIFIED_FILES=$(git status --short | head -5 | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    
    echo "⚠️  You have uncommitted changes in BillsAndBalance!"
    echo ""
    echo "Modified files ($MODIFIED_COUNT):"
    git status --short
    echo ""
    echo "💡 Consider committing your changes:"
    echo "   ./commit-changes.sh \"Your commit message\""
    echo ""
    
    # Show macOS notification
    if command -v osascript &> /dev/null; then
        osascript -e "display notification \"$MODIFIED_COUNT file(s) modified: $MODIFIED_FILES\" with title \"BillsAndBalance: Uncommitted Changes\" subtitle \"Consider committing your changes\" sound name \"Glass\""
    fi
else
    echo "✅ All changes are committed!"
fi
