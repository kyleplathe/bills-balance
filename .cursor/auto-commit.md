# Auto-Commit Setup Guide

## Quick Commit Script

Use the `commit-changes.sh` script to quickly commit and push changes:

```bash
./commit-changes.sh "Fixed build errors and added AccountEditorSheet"
```

## Reminder Script

The `.git-commit-reminder.sh` script checks for uncommitted changes and reminds you to commit.

### Manual Check
```bash
./.git-commit-reminder.sh
```

### Automated Reminder (macOS)

Add to your crontab to run every hour:
```bash
crontab -e
# Add this line:
0 * * * * /Volumes/Extreme\ Pro/Work/Dev\ Project/Bill\&Balance/.git-commit-reminder.sh
```

Or use macOS LaunchAgent for a GUI notification:

Create `~/Library/LaunchAgents/com.billsandbalance.commit-reminder.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.billsandbalance.commit-reminder</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Volumes/Extreme Pro/Work/Dev Project/Bill&Balance/.git-commit-reminder.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

Then load it:
```bash
launchctl load ~/Library/LaunchAgents/com.billsandbalance.commit-reminder.plist
```

## Best Practices

1. **Commit frequently** - After completing a feature or fixing a bug
2. **Use descriptive messages** - "Fixed build errors" not "fix"
3. **Push regularly** - At least once per day
4. **Test before committing** - Make sure the app builds and runs

## Current Status

Run `git status` to see current changes.
