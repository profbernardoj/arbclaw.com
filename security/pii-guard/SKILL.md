# PII Guard — Personal Data Leak Prevention for EverClaw

## Purpose
Prevents personal identifiable information (PII) from leaking to external services — GitHub repos, emails, social media, APIs, or any outbound data transfer.

## Components

### 1. Pattern File (User-Created, NEVER Committed)
```
~/.openclaw/workspace/.pii-patterns.json
```
Users populate this with their own protected data. A template is provided for first-run setup.

### 2. Git Pre-Push Hook (Global)
Automatically scans every `git push` on the machine. Blocks the push if PII is detected in the outgoing diff.

### 3. Scanner Script
Standalone scanner for files, directories, strings, or stdin. Called by the agent before any external action.

### 4. Agent Behavior
The agent MUST scan content before any outbound action:
- **HARD BLOCK** — Do not proceed when PII is detected
- **REPORT** — Show the user what was found, where, and which category
- **WAIT** — Only proceed after the user reviews and explicitly confirms override

## Setup

### First-Time Install
```bash
# Run the setup script (interactive)
bash ~/.openclaw/workspace/skills/everclaw/security/pii-guard/setup.sh
```

This will:
1. Create `~/.openclaw/workspace/.pii-patterns.json` from template (if not exists)
2. Install the global git pre-push hook
3. Add `.pii-patterns.json` to workspace `.gitignore`
4. Prompt the user to fill in their protected patterns

### Manual Install
```bash
# Copy template
cp ~/.openclaw/workspace/skills/everclaw/security/pii-guard/pii-patterns.template.json \
   ~/.openclaw/workspace/.pii-patterns.json

# Install global hook
git config --global core.hooksPath ~/.openclaw/workspace/scripts/git-hooks

# Edit patterns
nano ~/.openclaw/workspace/.pii-patterns.json
```

## Usage

### Scan a file or directory
```bash
pii-scan.sh <file_or_directory>
```

### Scan a string
```bash
pii-scan.sh --text "check this content before posting"
```

### Scan stdin
```bash
cat README.md | pii-scan.sh -
```

### Exit codes
- `0` — Clean, no PII found
- `1` — PII detected (blocked)
- `2` — Error (missing patterns file, missing jq, etc.)

## Pattern Categories

| Category | Examples | Why It Matters |
|----------|----------|---------------|
| `names` | Full names of you, family, associates | Identity exposure |
| `emails` | Personal/work email addresses | Contact info leak |
| `phones` | Phone numbers (all formats) | Contact info leak |
| `wallets` | Blockchain addresses (personal, not agent) | Financial exposure |
| `organizations` | Church, school, employer names | Location/affiliation exposure |
| `people` | Business contacts, missionaries, etc. | Third-party privacy |
| `websites` | Personal domains | Identity linkage |
| `keywords` | Any other protected strings | Catch-all |
| `regex` | Custom regex patterns (SSN, credit card, etc.) | Structured data |

## When the Agent Checks

**Mandatory before:**
- `git push` (automated via hook + agent double-check)
- Sending emails
- Posting to social media
- Publishing skills to ClawHub
- Creating/updating GitHub issues, PRs, discussions, comments
- Uploading files to any external service
- Any HTTP POST/PUT with user content

**Error format when blocked:**
```
🚫 PII GUARD: Blocked — personal data detected

Found in: <source>
Match: "<matched text>"
Category: <category>

Action blocked: <description>
To proceed: Remove the PII or explicitly confirm override.
```

## Security Notes
- `.pii-patterns.json` contains the very data it protects — **NEVER commit it**
- The template, scripts, and skill files are safe to publish (they contain no PII)
- The hook can be bypassed with `git push --no-verify` — use with extreme caution
- Adding patterns takes effect immediately — no restart needed
- Patterns are case-insensitive during scanning
